# FILE: app/routes/voice_routes.py
"""
Voice Recognition API Routes
Handles voice registration, identification, and user management

UPDATED: Added last_seen tracking for identified speakers
"""

from flask import Blueprint, request, jsonify
import os
import logging
from werkzeug.utils import secure_filename
from datetime import datetime
from pymongo import MongoClient
from pymongo.errors import ConnectionFailure, OperationFailure
import traceback

logger = logging.getLogger(__name__)

voice_bp = Blueprint('voice', __name__, url_prefix='/api/voice')


def allowed_audio_file(filename, allowed_extensions):
    """Check if audio file extension is allowed"""
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in allowed_extensions


def init_voice_routes(audio_processor, voice_service, mongo_uri, db_name, collection_name, config):
    """
    Initialize voice routes with dependencies

    Args:
        audio_processor: AudioProcessor instance
        voice_service: VoiceRecognitionService instance
        mongo_uri: MongoDB connection URI
        db_name: Database name
        collection_name: Collection name for voice users
        config: Configuration object
    """

    # Initialize MongoDB connection
    try:
        mongo_client = MongoClient(mongo_uri, serverSelectionTimeoutMS=5000)
        mongo_client.admin.command('ping')
        db = mongo_client[db_name]
        users_collection = db[collection_name]
        logger.info(f"✅ Voice Recognition MongoDB connected | Database: {db_name} | Collection: {collection_name}")
    except ConnectionFailure as e:
        logger.error(f"❌ Voice Recognition MongoDB connection failed: {e}")
        raise


    @voice_bp.route('/register', methods=['POST'])
    def register_user():
        """
        Register new user with voice samples

        Form Data:
            name: User's name (required)
            audio_files: List of audio files (required, 1-5 files)

        Returns:
            JSON: Registration result
        """
        logger.info("=" * 60)
        logger.info("📝 NEW VOICE REGISTRATION REQUEST")
        logger.info("=" * 60)

        try:
            # Validate user name
            if 'name' not in request.form:
                return jsonify({
                    "success": False,
                    "error": "User name is required"
                }), 400

            user_name = request.form['name'].strip()

            if not user_name or len(user_name) < 2:
                return jsonify({
                    "success": False,
                    "error": "User name must be at least 2 characters"
                }), 400

            logger.info(f"👤 User name: {user_name}")

            # Check if user already exists
            existing_user = users_collection.find_one({"name": user_name})
            if existing_user:
                logger.warning(f"⚠️  User '{user_name}' already exists")
                return jsonify({
                    "success": False,
                    "error": f"User '{user_name}' is already registered"
                }), 400

            # Validate audio files
            if 'audio_files' not in request.files:
                return jsonify({
                    "success": False,
                    "error": "Audio files are required"
                }), 400

            audio_files = request.files.getlist('audio_files')

            if len(audio_files) < 1 or len(audio_files) > 5:
                return jsonify({
                    "success": False,
                    "error": "Please provide 1-5 audio samples"
                }), 400

            logger.info(f"📊 Number of audio files: {len(audio_files)}")

            # Process audio files
            audio_paths = []
            processed_paths = []

            for i, audio_file in enumerate(audio_files, 1):
                # Validate file extension
                if not allowed_audio_file(audio_file.filename, config.ALLOWED_AUDIO_EXTENSIONS):
                    return jsonify({
                        "success": False,
                        "error": f"Invalid file format: {audio_file.filename}"
                    }), 400

                # Save uploaded file
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                filename = secure_filename(f"{user_name}_{timestamp}_sample{i}_{audio_file.filename}")
                filepath = os.path.join(config.UPLOAD_FOLDER, filename)

                audio_file.save(filepath)
                audio_paths.append(filepath)

                # Validate audio
                validation = audio_processor.validate_audio(
                    filepath,
                    min_duration=config.MIN_AUDIO_DURATION,
                    max_duration=config.MAX_AUDIO_DURATION
                )

                if not validation['valid']:
                    # Clean up
                    for path in audio_paths:
                        if os.path.exists(path):
                            os.remove(path)

                    return jsonify({
                        "success": False,
                        "error": f"Sample {i}: {validation['error']}"
                    }), 400

                # Preprocess audio
                try:
                    processed_audio, sr = audio_processor.preprocess(filepath)

                    processed_filename = filename.replace('.', '_processed.')
                    processed_path = os.path.join(config.UPLOAD_FOLDER, processed_filename)
                    audio_processor.save_audio(processed_audio, sr, processed_path)

                    processed_paths.append(processed_path)

                except Exception as e:
                    # Clean up
                    for path in audio_paths + processed_paths:
                        if os.path.exists(path):
                            os.remove(path)

                    return jsonify({
                        "success": False,
                        "error": f"Audio preprocessing failed: {str(e)}"
                    }), 500

            # Extract voice embeddings
            logger.info("🧠 Extracting voice embeddings...")
            registration_result = voice_service.register_voice(processed_paths, user_name)

            if not registration_result['success']:
                # Clean up
                for path in audio_paths + processed_paths:
                    if os.path.exists(path):
                        os.remove(path)

                return jsonify({
                    "success": False,
                    "error": registration_result.get('error', 'Voice registration failed')
                }), 500

            # Save to MongoDB
            logger.info("💾 Saving to database...")
            try:
                user_doc = {
                    "name": user_name,
                    "voice_embeddings": registration_result['embeddings'],
                    "num_samples": registration_result['num_samples'],
                    "avg_inter_similarity": registration_result.get('avg_inter_similarity', 0.0),
                    "registered_at": datetime.utcnow(),
                    "updated_at": datetime.utcnow(),
                    # ── NEW: last_seen starts as None until first identification ──
                    "last_seen": None
                }

                result = users_collection.insert_one(user_doc)
                user_id = str(result.inserted_id)

                logger.info(f"✅ User saved to database | ID: {user_id}")

            except OperationFailure as e:
                # Clean up
                for path in audio_paths + processed_paths:
                    if os.path.exists(path):
                        os.remove(path)

                return jsonify({
                    "success": False,
                    "error": f"Database error: {str(e)}"
                }), 500

            # Clean up temporary files
            for path in audio_paths + processed_paths:
                try:
                    if os.path.exists(path):
                        os.remove(path)
                except Exception as e:
                    logger.warning(f"⚠️  Failed to delete {path}: {e}")

            logger.info(f"✅ REGISTRATION SUCCESSFUL: {user_name}")

            return jsonify({
                "success": True,
                "message": f"User '{user_name}' registered successfully!",
                "user_id": user_id,
                "num_samples": registration_result['num_samples'],
                "avg_inter_similarity": round(registration_result.get('avg_inter_similarity', 0.0) * 100, 2)
            }), 201

        except Exception as e:
            logger.error(f"❌ Registration error: {e}")
            logger.error(traceback.format_exc())
            return jsonify({
                "success": False,
                "error": f"Server error: {str(e)}"
            }), 500


    @voice_bp.route('/identify', methods=['POST'])
    def identify_speaker():
        """
        Identify speaker from voice sample.

        After a successful identification the endpoint:
          1. Reads the current ``last_seen`` value from MongoDB and returns it
             in the response so the Flutter app can speak it aloud.
          2. Replaces ``last_seen`` in MongoDB with the **current** UTC timestamp.

        Form Data:
            audio_file: Audio file to identify (required)
            threshold:  Similarity threshold (optional)

        Returns:
            JSON: Identification result including ``last_seen`` (ISO string or null)
        """
        logger.info("=" * 60)
        logger.info("🔍 NEW VOICE IDENTIFICATION REQUEST")
        logger.info("=" * 60)

        try:
            if 'audio_file' not in request.files:
                return jsonify({
                    "success": False,
                    "error": "Audio file is required"
                }), 400

            audio_file = request.files['audio_file']

            if not allowed_audio_file(audio_file.filename, config.ALLOWED_AUDIO_EXTENSIONS):
                return jsonify({
                    "success": False,
                    "error": f"Invalid file format. Allowed: {', '.join(config.ALLOWED_AUDIO_EXTENSIONS)}"
                }), 400

            threshold = float(request.form.get('threshold', config.SIMILARITY_THRESHOLD))

            # Save file
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = secure_filename(f"identify_{timestamp}_{audio_file.filename}")
            filepath = os.path.join(config.UPLOAD_FOLDER, filename)
            audio_file.save(filepath)

            # Validate
            validation = audio_processor.validate_audio(filepath, config.MIN_AUDIO_DURATION, config.MAX_AUDIO_DURATION)
            if not validation['valid']:
                os.remove(filepath)
                return jsonify({"success": False, "error": validation['error']}), 400

            # Preprocess
            processed_audio, sr = audio_processor.preprocess(filepath)
            processed_path = filepath.replace('.', '_processed.')
            audio_processor.save_audio(processed_audio, sr, processed_path)

            # Get registered users (include last_seen field)
            registered_users = list(users_collection.find({}, {
                "_id": 1,
                "name": 1,
                "voice_embeddings": 1,
                "last_seen": 1
            }))

            # Run speaker identification
            result = voice_service.identify_speaker(processed_path, registered_users, threshold=threshold)

            # ── NEW: last_seen logic ─────────────────────────────────────────
            previous_last_seen = None   # what we will tell the user
            now_utc = datetime.utcnow()

            identified_name = result.get("name", "")
            is_real_person = (
                result.get("identified", False) and
                identified_name not in ("", "No users registered",
                                        "Unknown Person Speaking",
                                        "Can't hear someone speaking",
                                        "Error")
            )

            if is_real_person:
                # Find the matching user document to read current last_seen
                matched_user = next(
                    (u for u in registered_users if u["name"] == identified_name),
                    None
                )

                if matched_user:
                    previous_last_seen = matched_user.get("last_seen")   # may be None on first meet

                    # Overwrite last_seen with current detection time
                    users_collection.update_one(
                        {"name": identified_name},
                        {"$set": {
                            "last_seen": now_utc,
                            "updated_at": now_utc
                        }}
                    )
                    logger.info(
                        f"📅 last_seen updated for '{identified_name}' | "
                        f"previous={previous_last_seen} → new={now_utc.isoformat()}"
                    )

            # Attach last_seen to the result (ISO string or None)
            result["last_seen"] = (
                previous_last_seen.isoformat() + "Z"
                if isinstance(previous_last_seen, datetime)
                else None
            )
            # ────────────────────────────────────────────────────────────────

            # Clean up temp files
            try:
                os.remove(filepath)
                os.remove(processed_path)
            except Exception:
                pass

            logger.info("✅ Identification complete")

            return jsonify({
                "success": True,
                "result": result
            }), 200

        except Exception as e:
            logger.error(f"❌ Identification error: {e}")
            logger.error(traceback.format_exc())
            return jsonify({
                "success": False,
                "error": f"Server error: {str(e)}"
            }), 500


    @voice_bp.route('/users', methods=['GET'])
    def get_users():
        """Get all registered voice users"""
        try:
            users = list(users_collection.find({}, {
                "_id": 1,
                "name": 1,
                "num_samples": 1,
                "avg_inter_similarity": 1,
                "registered_at": 1,
                "last_seen": 1      # ── NEW: expose last_seen in listing
            }))

            users_info = []
            for user in users:
                last_seen_val = user.get("last_seen")
                users_info.append({
                    "id": str(user['_id']),
                    "name": user['name'],
                    "num_samples": user.get('num_samples', 0),
                    "avg_inter_similarity": round(user.get('avg_inter_similarity', 0.0) * 100, 2),
                    "registered_at": user.get('registered_at', '').isoformat() if user.get('registered_at') else None,
                    # ── NEW ──
                    "last_seen": (last_seen_val.isoformat() + "Z") if isinstance(last_seen_val, datetime) else None
                })

            return jsonify({
                "success": True,
                "users": users_info,
                "total": len(users_info)
            }), 200

        except Exception as e:
            logger.error(f"❌ Get users error: {e}")
            return jsonify({
                "success": False,
                "error": str(e)
            }), 500


    @voice_bp.route('/users/<user_name>', methods=['DELETE'])
    def delete_user(user_name):
        """Delete user by name"""
        try:
            result = users_collection.delete_one({"name": user_name})

            if result.deleted_count > 0:
                return jsonify({
                    "success": True,
                    "message": f"User '{user_name}' deleted successfully"
                }), 200
            else:
                return jsonify({
                    "success": False,
                    "message": f"User '{user_name}' not found"
                }), 404

        except Exception as e:
            logger.error(f"❌ Delete user error: {e}")
            return jsonify({
                "success": False,
                "error": str(e)
            }), 500


    @voice_bp.route('/verify', methods=['POST'])
    def verify_speaker():
        """Verify if speaker matches claimed identity"""
        try:
            if 'audio_file' not in request.files or 'claimed_name' not in request.form:
                return jsonify({
                    "success": False,
                    "error": "Audio file and claimed name are required"
                }), 400

            audio_file = request.files['audio_file']
            claimed_name = request.form['claimed_name'].strip()
            threshold = float(request.form.get('threshold', config.SIMILARITY_THRESHOLD))

            # Save and preprocess
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = secure_filename(f"verify_{timestamp}_{audio_file.filename}")
            filepath = os.path.join(config.UPLOAD_FOLDER, filename)
            audio_file.save(filepath)

            processed_audio, sr = audio_processor.preprocess(filepath)
            processed_path = filepath.replace('.', '_processed.')
            audio_processor.save_audio(processed_audio, sr, processed_path)

            # Get users
            registered_users = list(users_collection.find())

            # Verify
            result = voice_service.verify_speaker(processed_path, claimed_name, registered_users, threshold)

            # Clean up
            os.remove(filepath)
            os.remove(processed_path)

            return jsonify({
                "success": True,
                "result": result
            }), 200

        except Exception as e:
            logger.error(f"❌ Verification error: {e}")
            return jsonify({
                "success": False,
                "error": str(e)
            }), 500


    return voice_bp