import numpy as np

CONF_THRESHOLD = 0.35
FRAME_WIDTH = 640
FRAME_HEIGHT = 480

FACE_LABELS = {"face", "human face"}

TYPICAL_HEIGHTS_M = {
    "person": 1.7,
    "chair": 0.9,
    "bottle": 0.25,
    "cup": 0.1,
    "cell phone": 0.15,
    "car": 1.5,
    "truck": 2.0,
    "bus": 3.0,
    "cat": 0.25,
    "dog": 0.5,
    "table": 0.8,
    "door": 2.0,
    "door_open": 2.0,
    "door_closed": 2.0,
    "door_half_open": 2.0,
    "stairs": 1.2,
    "stairs_up": 1.2,
    "stairs_down": 1.2,
    "bench": 0.5,
    "couch": 0.9,
    "bed": 0.6,
    "laptop": 0.3,
    "tv": 0.6,
    "refrigerator": 1.8,
}

# ✅ NEW: Objects that fill the frame when close (use bbox coverage instead)
LARGE_OBJECTS = {"door", "door_open", "door_closed", "door_half_open", "stairs", "wall", "refrigerator"}

FOCAL_LENGTH = 500
calibrated_focal_lengths = {}


def format_label_for_speech(label: str) -> str:
    """Convert label to speech-friendly format"""
    clean = label.replace("_", " ").replace("-", " ")
    return clean


def relative_position(cx: float, frame_w: int) -> str:
    third = frame_w / 3
    if cx < third:
        return "left"
    if cx > 2 * third:
        return "right"
    return "center"


def estimate_distance(bbox, label: str = "", frame_width: int = 480, frame_height: int = 480) -> float | None:
    """
    Estimate distance using bbox height OR bbox coverage for large objects.
    """
    x1, y1, x2, y2 = bbox
    bbox_height_px = abs(y2 - y1)
    bbox_width_px = abs(x2 - x1)
    
    if bbox_height_px <= 0:
        return None

    label_lower = label.lower()
    if label_lower in FACE_LABELS:
        return None

    # ✅ NEW: For large objects (doors, stairs), use COVERAGE-based distance
    if label_lower in LARGE_OBJECTS:
        return _estimate_distance_by_coverage(bbox, frame_width, frame_height, label_lower)

    # Standard height-based calculation for other objects
    real_height_m = TYPICAL_HEIGHTS_M.get(label_lower, 0.8)
    focal = calibrated_focal_lengths.get(label_lower, FOCAL_LENGTH)

    try:
        distance = (real_height_m * focal) / bbox_height_px
        return float(max(0.1, min(distance, 15.0)))
    except:
        return None


def _estimate_distance_by_coverage(bbox, frame_width: int, frame_height: int, label: str) -> float:
    """
    Estimate distance based on how much of the frame the object covers.
    More coverage = closer to camera.
    """
    x1, y1, x2, y2 = bbox
    bbox_width = abs(x2 - x1)
    bbox_height = abs(y2 - y1)
    
    # Calculate coverage percentage
    bbox_area = bbox_width * bbox_height
    frame_area = frame_width * frame_height
    coverage = bbox_area / frame_area
    
    # Also check height coverage (important for doors)
    height_coverage = bbox_height / frame_height
    width_coverage = bbox_width / frame_width
    
    # Use the maximum coverage dimension
    max_coverage = max(height_coverage, width_coverage, coverage)
    
    print(f"   📐 {label} coverage: {coverage:.2%}, height: {height_coverage:.2%}, width: {width_coverage:.2%}")
    
    # ✅ Coverage-to-distance mapping for doors/large objects
    if max_coverage >= 0.85:
        # Almost filling frame = very close
        distance = 0.3
    elif max_coverage >= 0.70:
        distance = 0.5
    elif max_coverage >= 0.55:
        distance = 0.8
    elif max_coverage >= 0.45:
        distance = 1.0
    elif max_coverage >= 0.35:
        distance = 1.3
    elif max_coverage >= 0.25:
        distance = 1.8
    elif max_coverage >= 0.15:
        distance = 2.5
    elif max_coverage >= 0.10:
        distance = 3.5
    else:
        distance = 5.0
    
    print(f"   📏 {label} estimated distance: {distance:.1f}m (coverage-based)")
    
    return float(distance)


def get_detection_info(det: dict, frame_width: int, frame_height: int = 480, midas_distance: float = None) -> dict:
    """
    Get detection info with improved distance calculation.
    """
    x1, y1, x2, y2 = det["bbox"]
    cx = (x1 + x2) / 2
    bbox_height = abs(y2 - y1)

    label = det.get("label", "object")
    conf = float(det.get("conf", 0))
    
    # ✅ Updated: Pass full bbox for coverage calculation
    bbox_distance = estimate_distance(det["bbox"], label, frame_width, frame_height)
    
    # ✅ For large objects, prefer bbox coverage over MiDaS
    label_lower = label.lower()
    if label_lower in LARGE_OBJECTS:
        # Trust coverage-based calculation more for large objects
        if bbox_distance is not None and midas_distance is not None:
            # Weighted: 70% coverage, 30% MiDaS
            distance = bbox_distance * 0.7 + midas_distance * 0.3
        else:
            distance = bbox_distance
    else:
        # Standard hybrid approach for other objects
        if midas_distance is not None and bbox_distance is not None:
            if midas_distance < 2.0:
                distance = midas_distance * 0.7 + bbox_distance * 0.3
            else:
                distance = midas_distance * 0.3 + bbox_distance * 0.7
        elif midas_distance is not None:
            distance = midas_distance
        else:
            distance = bbox_distance
    
    position = relative_position(cx, frame_width)
    speech_label = format_label_for_speech(label)

    return {
        "label": label,
        "speech_label": speech_label,
        "conf": conf,
        "distance": distance,
        "position": position,
        "bbox": [x1, y1, x2, y2],
    }


def format_distance(dist_m: float | None) -> str:
    if dist_m is None:
        return "unknown distance"
    if dist_m < 0.1:
        return "very close"
    return f"{dist_m:.1f} meters"


def iou(boxA, boxB):
    xA = max(boxA[0], boxB[0])
    yA = max(boxA[1], boxB[1])
    xB = min(boxA[2], boxB[2])
    yB = min(boxA[3], boxB[3])

    interW = max(0, xB - xA)
    interH = max(0, yB - yA)
    interArea = interW * interH

    if interArea == 0:
        return 0.0

    boxAArea = (boxA[2] - boxA[0]) * (boxA[3] - boxA[1])
    boxBArea = (boxB[2] - boxB[0]) * (boxB[3] - boxB[1])

    return interArea / float(boxAArea + boxBArea - interArea)


def simple_nms(detections, iou_thresh=0.5):
    if not detections:
        return []

    dets = sorted(detections, key=lambda x: x.get("conf", 0), reverse=True)
    keep = []

    while dets:
        best = dets.pop(0)
        keep.append(best)

        remaining = []
        for d in dets:
            if iou(best["bbox"], d["bbox"]) < iou_thresh:
                remaining.append(d)
        dets = remaining

    return keep


def custom_priority(detections):
    if not detections:
        return []

    custom_labels = {"door_closed", "door_open", "door_half_open", "stairs"}

    custom_dets = [d for d in detections if d.get("label") in custom_labels]
    yolo_dets = [d for d in detections if d.get("label") not in custom_labels]

    if not custom_dets:
        return detections

    filtered_yolo = []
    for yd in yolo_dets:
        overlapped = False
        for cd in custom_dets:
            if iou(yd["bbox"], cd["bbox"]) > 0.45:
                overlapped = True
                break
        if not overlapped:
            filtered_yolo.append(yd)

    return custom_dets + filtered_yolo