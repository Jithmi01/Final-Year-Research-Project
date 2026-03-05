# FILE: app/routes/voice_routes.py
"""
Voice Recognition API Routes
Handles voice registration, identification, and user management

UPDATED: Added last_seen tracking for identified speakers
UPDATED: Added speech transcription & Sinhala translation for identified speakers
UPDATED: Added /transcribe-command endpoint for voice command detection
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


def init_voice_routes(audio_processor, voice_service, translation_service,
                      mongo_uri, db_name, collection_name, config):
    """
    Initialize voice routes with dependencies

    Args:
        audio_processor:     AudioProcessor instance
        voice_service:       VoiceRecognitionService instance
        translation_service: TranslationService instance (or None if unavailable)
        mongo_uri:           MongoDB connection URI
        db_name:             Database name
        collection_name:     Collection name for voice users
        config:              Configuration object
    """

    # Initialize MongoDB connection
    try:
        mongo_client = MongoClient(mongo_uri, serverSelectionTimeoutMS=5000)
        mongo_client.admin.command('ping')
        db = mongo_client[db_name]
        users_collection = db[collection_name]
        logger.info(
            f"✅ Voice Recognition MongoDB connected | "
            f"Database: {db_name} | Collection: {collection_name}"
        )
    except ConnectionFailure as e:
        logger.error(f"❌ Voice Recognition MongoDB connection failed: {e}")
        raise

    # ═══════════════════════════════════════════════════════════════════════
    # REGISTER
    # ═══════════════════════════════════════════════════════════════════════

    @voice_bp.route('/register', methods=['POST'])
    def register_user():
        """
        Register new user with voice samples.

        Form Data:
            name:        User's name (required)
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

            audio_paths     = []
            processed_paths = []

            for i, audio_file in enumerate(audio_files, 1):
                if not allowed_audio_file(audio_file.filename,
                                          config.ALLOWED_AUDIO_EXTENSIONS):
                    return jsonify({
                        "success": False,
                        "error": f"Invalid file format: {audio_file.filename}"
                    }), 400

                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                filename  = secure_filename(
                    f"{user_name}_{timestamp}_sample{i}_{audio_file.filename}"
                )
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
                    processed_filename  = filename.replace('.', '_processed.')
                    processed_path      = os.path.join(
                        config.UPLOAD_FOLDER, processed_filename
                    )
                    audio_processor.save_audio(processed_audio, sr, processed_path)
                    processed_paths.append(processed_path)

                except Exception as e:
                    for path in audio_paths + processed_paths:
                        if os.path.exists(path):
                            os.remove(path)
                    return jsonify({
                        "success": False,
                        "error": f"Audio preprocessing failed: {str(e)}"
                    }), 500

            # Extract voice embeddings
            logger.info("🧠 Extracting voice embeddings...")
            registration_result = voice_service.register_voice(
                processed_paths, user_name
            )

            if not registration_result['success']:
                for path in audio_paths + processed_paths:
                    if os.path.exists(path):
                        os.remove(path)
                return jsonify({
                    "success": False,
                    "error": registration_result.get('error',
                                                     'Voice registration failed')
                }), 500

            # Save to MongoDB
            logger.info("💾 Saving to database...")
            try:
                user_doc = {
                    "name":               user_name,
                    "voice_embeddings":   registration_result['embeddings'],
                    "num_samples":        registration_result['num_samples'],
                    "avg_inter_similarity": registration_result.get(
                        'avg_inter_similarity', 0.0
                    ),
                    "registered_at": datetime.utcnow(),
                    "updated_at":    datetime.utcnow(),
                    "last_seen":     None
                }

                result  = users_collection.insert_one(user_doc)
                user_id = str(result.inserted_id)
                logger.info(f"✅ User saved to database | ID: {user_id}")

            except OperationFailure as e:
                for path in audio_paths + processed_paths:
                    if os.path.exists(path):
                        os.remove(path)
                return jsonify({
                    "success": False,
                    "error": f"Database error: {str(e)}"
                }), 500

            # Clean up
            for path in audio_paths + processed_paths:
                try:
                    if os.path.exists(path):
                        os.remove(path)
                except Exception as e:
                    logger.warning(f"⚠️  Failed to delete {path}: {e}")

            logger.info(f"✅ REGISTRATION SUCCESSFUL: {user_name}")

            return jsonify({
                "success":            True,
                "message":            f"User '{user_name}' registered successfully!",
                "user_id":            user_id,
                "num_samples":        registration_result['num_samples'],
                "avg_inter_similarity": round(
                    registration_result.get('avg_inter_similarity', 0.0) * 100, 2
                )
            }), 201

        except Exception as e:
            logger.error(f"❌ Registration error: {e}")
            logger.error(traceback.format_exc())
            return jsonify({
                "success": False,
                "error": f"Server error: {str(e)}"
            }), 500

    # ═══════════════════════════════════════════════════════════════════════
    # IDENTIFY
    # ═══════════════════════════════════════════════════════════════════════

    @voice_bp.route('/identify', methods=['POST'])
    def identify_speaker():
        """
        Identify speaker from voice sample.

        After a successful identification the endpoint:
          1. Reads the current last_seen value from MongoDB and returns it.
          2. Replaces last_seen with the current UTC timestamp.
          3. Transcribes what the speaker said using Whisper STT.
          4. If the spoken language differs from target_language, translates it.
             Translation only runs for positively identified known speakers.

        Form Data:
            audio_file:          Audio file to identify (required)
            threshold:           Similarity threshold (optional)
            enable_translation:  'true' / 'false' (optional, default 'true')
            target_language:     ISO-639-1 code, e.g. 'si', 'en', 'ta'
                                 (optional, default 'si')

        Returns:
            JSON with identification result, last_seen, and translation block.
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

            if not allowed_audio_file(audio_file.filename,
                                      config.ALLOWED_AUDIO_EXTENSIONS):
                return jsonify({
                    "success": False,
                    "error": (f"Invalid file format. "
                              f"Allowed: {', '.join(config.ALLOWED_AUDIO_EXTENSIONS)}")
                }), 400

            threshold           = float(request.form.get(
                'threshold', config.SIMILARITY_THRESHOLD
            ))
            enable_translation  = request.form.get(
                'enable_translation', 'true'
            ).lower() == 'true'
            target_language     = request.form.get('target_language', 'si')

            # ── Save original file (Whisper needs the raw audio) ─────────────
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename  = secure_filename(
                f"identify_{timestamp}_{audio_file.filename}"
            )
            filepath  = os.path.join(config.UPLOAD_FOLDER, filename)
            audio_file.save(filepath)

            # ── Validate ─────────────────────────────────────────────────────
            validation = audio_processor.validate_audio(
                filepath,
                config.MIN_AUDIO_DURATION,
                config.MAX_AUDIO_DURATION
            )
            if not validation['valid']:
                os.remove(filepath)
                return jsonify({
                    "success": False,
                    "error": validation['error']
                }), 400

            # ── Preprocess for speaker identification ─────────────────────────
            processed_audio, sr = audio_processor.preprocess(filepath)
            processed_path      = filepath.replace('.', '_processed.')
            audio_processor.save_audio(processed_audio, sr, processed_path)

            # ── Fetch registered users ────────────────────────────────────────
            registered_users = list(users_collection.find({}, {
                "_id": 1,
                "name": 1,
                "voice_embeddings": 1,
                "last_seen": 1
            }))

            # ── Speaker identification ────────────────────────────────────────
            result = voice_service.identify_speaker(
                processed_path, registered_users, threshold=threshold
            )

            # ── last_seen logic (unchanged) ───────────────────────────────────
            previous_last_seen = None
            now_utc            = datetime.utcnow()

            identified_name = result.get("name", "")
            is_real_person  = (
                result.get("identified", False) and
                identified_name not in (
                    "", "No users registered",
                    "Unknown Person Speaking",
                    "Can't hear someone speaking",
                    "Error"
                )
            )

            if is_real_person:
                matched_user = next(
                    (u for u in registered_users
                     if u["name"] == identified_name),
                    None
                )
                if matched_user:
                    previous_last_seen = matched_user.get("last_seen")
                    users_collection.update_one(
                        {"name": identified_name},
                        {"$set": {"last_seen": now_utc, "updated_at": now_utc}}
                    )
                    logger.info(
                        f"📅 last_seen updated for '{identified_name}' | "
                        f"previous={previous_last_seen} → new={now_utc.isoformat()}"
                    )

            result["last_seen"] = (
                previous_last_seen.isoformat() + "Z"
                if isinstance(previous_last_seen, datetime)
                else None
            )

            # ── Transcription & translation ───────────────────────────────────
            # Default empty block — always present so Flutter never key-errors.
            translation_data = {
                "transcribed_text":  None,
                "detected_language": None,
                "is_already_target": False,
                "translated_text":   None,
                "target_language":   target_language,
                "translation_error": None,
            }

            # Only run when:
            #   • translation is enabled
            #   • TranslationService is available
            #   • A real registered person was identified
            if enable_translation and translation_service is not None \
                    and is_real_person:
                try:
                    logger.info(
                        f"🌐 Transcribing & translating for "
                        f"'{identified_name}' → target='{target_language}'..."
                    )
                    # Use original (raw) file for best Whisper accuracy
                    translation_data = translation_service.transcribe_and_translate(
                        filepath, target_language=target_language
                    )
                    logger.info(
                        f"✅ Translation done | "
                        f"lang={translation_data.get('detected_language')} | "
                        f"already_target={translation_data.get('is_already_target')} | "
                        f"text='{translation_data.get('translated_text')}'"
                    )
                except Exception as te:
                    logger.error(f"⚠️  Translation step failed (non-fatal): {te}")
                    translation_data["translation_error"] = str(te)

            elif enable_translation and translation_service is None:
                translation_data["translation_error"] = (
                    "Translation service not initialized"
                )
                logger.warning(
                    "⚠️  Translation requested but TranslationService is None"
                )

            elif not is_real_person:
                logger.info(
                    f"ℹ️  Skipping translation — not a known registered person "
                    f"(name='{identified_name}')"
                )

            result["translation"] = translation_data

            # ── Clean up temp files ───────────────────────────────────────────
            # Original file deleted AFTER translation (Whisper reads it above)
            try:
                if os.path.exists(filepath):
                    os.remove(filepath)
                if os.path.exists(processed_path):
                    os.remove(processed_path)
            except Exception as cleanup_err:
                logger.warning(f"⚠️  Temp file cleanup warning: {cleanup_err}")

            logger.info("✅ Identification complete")
            return jsonify({"success": True, "result": result}), 200

        except Exception as e:
            logger.error(f"❌ Identification error: {e}")
            logger.error(traceback.format_exc())
            return jsonify({
                "success": False,
                "error": f"Server error: {str(e)}"
            }), 500

    # ═══════════════════════════════════════════════════════════════════════
    # TRANSCRIBE COMMAND
    # ═══════════════════════════════════════════════════════════════════════

    @voice_bp.route('/transcribe-command', methods=['POST'])
    def transcribe_command():
        """
        Transcribe a short voice command clip.
        Used by the Flutter app to detect keywords like 'translate'.
        Runs Whisper STT only — no speaker identification, no translation.

        Form Data:
            audio_file: Short audio clip (required, typically 3 seconds)

        Returns:
            JSON: { "transcribed_text": "..." }
            Always returns 200 — empty string on any failure so the
            Flutter caller can handle gracefully.
        """
        try:
            if 'audio_file' not in request.files:
                return jsonify({"transcribed_text": ""}), 200

            audio_file = request.files['audio_file']

            if not allowed_audio_file(audio_file.filename,
                                      config.ALLOWED_AUDIO_EXTENSIONS):
                return jsonify({"transcribed_text": ""}), 200

            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename  = secure_filename(
                f"cmd_{timestamp}_{audio_file.filename}"
            )
            filepath  = os.path.join(config.UPLOAD_FOLDER, filename)
            audio_file.save(filepath)

            transcribed_text = ""

            if translation_service is not None:
                try:
                    import torch
                    whisper_result   = translation_service.whisper_model.transcribe(
                        filepath,
                        fp16=torch.cuda.is_available()
                    )
                    transcribed_text = whisper_result.get("text", "").strip()
                    logger.info(
                        f"🎤 Command transcription: '{transcribed_text}'"
                    )
                except Exception as e:
                    logger.warning(
                        f"⚠️  Command transcription failed (non-fatal): {e}"
                    )
            else:
                logger.warning(
                    "⚠️  transcribe-command: TranslationService not available"
                )

            # Clean up
            try:
                if os.path.exists(filepath):
                    os.remove(filepath)
            except Exception:
                pass

            return jsonify({"transcribed_text": transcribed_text}), 200

        except Exception as e:
            logger.error(f"❌ Command transcription error: {e}")
            return jsonify({"transcribed_text": ""}), 200

    # ═══════════════════════════════════════════════════════════════════════
    # GET USERS
    # ═══════════════════════════════════════════════════════════════════════

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
                "last_seen": 1
            }))

            users_info = []
            for user in users:
                last_seen_val = user.get("last_seen")
                users_info.append({
                    "id":   str(user['_id']),
                    "name": user['name'],
                    "num_samples": user.get('num_samples', 0),
                    "avg_inter_similarity": round(
                        user.get('avg_inter_similarity', 0.0) * 100, 2
                    ),
                    "registered_at": (
                        user['registered_at'].isoformat()
                        if user.get('registered_at') else None
                    ),
                    "last_seen": (
                        last_seen_val.isoformat() + "Z"
                        if isinstance(last_seen_val, datetime) else None
                    )
                })

            return jsonify({
                "success": True,
                "users":   users_info,
                "total":   len(users_info)
            }), 200

        except Exception as e:
            logger.error(f"❌ Get users error: {e}")
            return jsonify({"success": False, "error": str(e)}), 500

    # ═══════════════════════════════════════════════════════════════════════
    # DELETE USER
    # ═══════════════════════════════════════════════════════════════════════

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
            return jsonify({"success": False, "error": str(e)}), 500

    # ═══════════════════════════════════════════════════════════════════════
    # VERIFY
    # ═══════════════════════════════════════════════════════════════════════

    @voice_bp.route('/verify', methods=['POST'])
    def verify_speaker():
        """Verify if speaker matches claimed identity"""
        try:
            if ('audio_file' not in request.files or
                    'claimed_name' not in request.form):
                return jsonify({
                    "success": False,
                    "error": "Audio file and claimed name are required"
                }), 400

            audio_file   = request.files['audio_file']
            claimed_name = request.form['claimed_name'].strip()
            threshold    = float(request.form.get(
                'threshold', config.SIMILARITY_THRESHOLD
            ))

            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename  = secure_filename(
                f"verify_{timestamp}_{audio_file.filename}"
            )
            filepath  = os.path.join(config.UPLOAD_FOLDER, filename)
            audio_file.save(filepath)

            processed_audio, sr = audio_processor.preprocess(filepath)
            processed_path      = filepath.replace('.', '_processed.')
            audio_processor.save_audio(processed_audio, sr, processed_path)

            registered_users = list(users_collection.find())

            result = voice_service.verify_speaker(
                processed_path, claimed_name, registered_users, threshold
            )

            try:
                os.remove(filepath)
                os.remove(processed_path)
            except Exception:
                pass

            return jsonify({"success": True, "result": result}), 200

        except Exception as e:
            logger.error(f"❌ Verification error: {e}")
            return jsonify({
                "success": False,
                "error": str(e)
            }), 500

    return voice_bp