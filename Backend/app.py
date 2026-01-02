import base64
import cv2
import numpy as np
from flask import Flask, request, jsonify
from flask_cors import CORS
from ultralytics import YOLO
import time
import torch

import core
from depth_estimator import DepthEstimator
from navigation_engine import get_navigation_for_response

# ✅ Object Finder imports
from object_finder.detection import MultiModelDetector, process_frame
from object_finder.voice import build_object_map, process_voice_command_text
from object_finder.state import state as finder_state


MODEL_PATH = "yolov8m-oiv7.pt"
CUSTOM_MODEL_PATH = "models/door_stairs_model.pt"

app = Flask(__name__)
CORS(app)

print("=" * 50)
print("🚀 FAST BLIND ASSIST SERVER v2")
print("=" * 50)

# ==========================================
# LOAD MODELS
# ==========================================
print("Loading models...")
model = YOLO(MODEL_PATH)

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
print(f"📱 Device: {DEVICE}")

# ✅ Warm up base model
dummy = np.zeros((480, 480, 3), dtype=np.uint8)
model(dummy, verbose=False)
print("✅ YOLO warmed up")

# ✅ Load custom model
custom_model = None
try:
    custom_model = YOLO(CUSTOM_MODEL_PATH)
    custom_model(dummy, verbose=False)
    print(f"✅ Custom model: {custom_model.names}")
except Exception as e:
    print(f"⚠️ Custom model: {e}")

# ✅ Load MiDaS depth model
depth_estimator = None
try:
    depth_estimator = DepthEstimator(model_type="MiDaS_small")
    depth_estimator.estimate_depth(dummy)
    print("✅ MiDaS warmed up")
except Exception as e:
    print(f"⚠️ MiDaS: {e}")


# ==========================================
# OBJECT FINDER MODE INIT
# ==========================================
finder_detector = MultiModelDetector(model, custom_model)

# ✅ FIXED: Now returns tuple (obj_map, exact_names)
finder_object_map, finder_exact_names = build_object_map(
    model.names,
    custom_model.names if custom_model else None
)
print(f"✅ Finder mode ready | Objects supported: {len(set(finder_object_map.values()))}")
print(f"✅ Exact YOLO names: {len(finder_exact_names)}")


# ==========================================
# PERFORMANCE TRACKING
# ==========================================
times = []


# ==========================================
# HELPERS
# ==========================================
def parse_results(result, source: str):
    detections = []
    boxes = getattr(result, "boxes", None)
    if boxes is None:
        return detections

    names = result.names
    for box in boxes:
        try:
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            conf = float(box.conf[0])
            cls_id = int(box.cls[0])
            label = names.get(cls_id, str(cls_id)) if isinstance(names, dict) else names[cls_id]

            detections.append({
                "bbox": [x1, y1, x2, y2],
                "conf": conf,
                "label": str(label),
                "source": source
            })
        except:
            continue

    return detections


def run_detection(frame):
    detections = []

    # Base YOLO
    results = model(frame, conf=0.25, iou=0.5, verbose=False)
    detections.extend(parse_results(results[0], "yolo"))

    # Custom YOLO
    if custom_model:
        try:
            results2 = custom_model(frame, conf=0.35, iou=0.5, verbose=False)
            for d in parse_results(results2[0], "custom"):
                label = d["label"].lower().strip()
                label_map = {
                    "door-closed": "door_closed",
                    "door-open": "door_open",
                    "door-half-open": "door_half_open",
                    "stairs": "stairs",
                }
                if label in label_map:
                    d["label"] = label_map[label]
                    detections.append(d)
        except:
            pass

    detections = core.simple_nms(detections, iou_thresh=0.5)

    # ⚠️ FIX: core.custom_priority may return tuple due to trailing comma bug
    prioritized = core.custom_priority(detections)
    if isinstance(prioritized, tuple):
        prioritized = prioritized[0]
    detections = prioritized

    return detections


# ==========================================
# ROUTES
# ==========================================
@app.route("/ping", methods=["GET"])
def ping():
    avg = sum(times) / len(times) * 1000 if times else 0
    return jsonify({"status": "ok", "avg_ms": round(avg, 1), "device": DEVICE})


@app.route("/detect", methods=["POST"])
def detect():
    t0 = time.time()

    data = request.json
    if not data or "image" not in data:
        return jsonify({"error": "Missing image"}), 400

    try:
        # Decode image
        img_bytes = base64.b64decode(data["image"])
        frame = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR)

        if frame is None:
            return jsonify({"error": "Invalid image"}), 400

        # Resize for speed
        h, w = frame.shape[:2]
        target_size = 480
        if w != target_size or h != target_size:
            frame = cv2.resize(frame, (target_size, target_size), interpolation=cv2.INTER_LINEAR)
            h, w = target_size, target_size

        core.FRAME_WIDTH = w
        core.FRAME_HEIGHT = h

        # Depth map
        depth_map = None
        if depth_estimator:
            try:
                depth_map = depth_estimator.estimate_depth(frame)
            except:
                pass

        # Detection
        detections = run_detection(frame)

        # Process results
        det_infos = []
        for det in detections:
            if det["conf"] < core.CONF_THRESHOLD:
                continue

            x1, y1, x2, y2 = det["bbox"]
            if (x2 - x1) * (y2 - y1) < 400:
                continue

            midas_dist = None
            if depth_map is not None:
                try:
                    midas_dist = depth_estimator.get_distance_at_bbox(depth_map, det["bbox"])
                except:
                    midas_dist = None

            det_infos.append(core.get_detection_info(det, w, frame_height=h, midas_distance=midas_dist))

        # Navigation
        navigation = get_navigation_for_response(det_infos)

        # Performance
        elapsed = time.time() - t0
        times.append(elapsed)
        if len(times) > 50:
            times.pop(0)

        # Compact log
        objs = ", ".join([f"{o['label'][:8]}({o['distance']:.1f}m)" for o in det_infos[:3]])
        print(f"⚡{elapsed*1000:.0f}ms | {navigation['command'][:10]} | {objs or 'clear'}")

        return jsonify({
            "img_w": w,
            "img_h": h,
            "objects": det_infos,
            "navigation": navigation,
            "ms": round(elapsed * 1000, 1)
        })

    except Exception as e:
        print(f"❌ {e}")
        return jsonify({"error": str(e)}), 500


# ==========================================
# FINDER ROUTES (Object Search Mode)
# ==========================================
@app.route("/finder/status", methods=["GET"])
def finder_status():
    return jsonify({
        "ok": True,
        "target": finder_state.current_target,
        "show_all": finder_state.show_all,
        "state": finder_state.current_state
    })


@app.route("/finder/command", methods=["POST"])
def finder_command():
    data = request.json
    if not data or "command" not in data:
        return jsonify({"ok": False, "error": "Missing command"}), 400

    cmd = str(data["command"]).strip().lower()
    if not cmd:
        return jsonify({"ok": False, "error": "Empty command"}), 400

    # ✅ FIXED: Pass exact_names parameter
    result = process_voice_command_text(cmd, finder_object_map, finder_exact_names)

    return jsonify({
        "ok": True,
        "input": cmd,
        "result": result,
        "target": finder_state.current_target,
        "show_all": finder_state.show_all
    })


@app.route("/finder/detect", methods=["POST"])
def finder_detect():
    t0 = time.time()

    data = request.json
    if not data or "image" not in data:
        return jsonify({"ok": False, "error": "Missing image"}), 400

    try:
        img_bytes = base64.b64decode(data["image"])
        frame = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR)

        if frame is None:
            return jsonify({"ok": False, "error": "Invalid image"}), 400

        # Resize for speed
        target_size = 480
        h, w = frame.shape[:2]
        if w != target_size or h != target_size:
            frame = cv2.resize(frame, (target_size, target_size), interpolation=cv2.INTER_LINEAR)

        # Process frame using finder detector
        _, info = process_frame(
            frame=frame,
            detector=finder_detector,
            tts=None,  # Flutter handles TTS
            current_target=finder_state.current_target
        )

        elapsed = (time.time() - t0) * 1000

        return jsonify({
            "ok": True,
            "target": finder_state.current_target,
            "show_all": finder_state.show_all,
            "info": info,
            "ms": round(elapsed, 1)
        })

    except Exception as e:
        print(f"❌ Finder error: {e}")
        return jsonify({"ok": False, "error": str(e)}), 500


# ==========================================
# RUN
# ==========================================
print("✅ APP.PY LOADED ✅")
print("✅ ROUTES:", app.url_map)
if __name__ == "__main__":
    print("\n🌐 Starting on http://0.0.0.0:5000\n")
    app.run(host="0.0.0.0", port=5000, debug=False, threaded=True)