# FILE: services/translation_service.py
"""
Speech Transcription & Translation Service
- Transcribes audio to text using OpenAI Whisper (local, free)
- Detects language of transcribed text
- Translates to ANY target language using deep-translator
  (target language is passed per-request, not hardcoded to Sinhala)

Only activated AFTER a speaker has already been identified.
Does NOT affect voice identification logic at all.
"""

import whisper
import logging
import os
import torch

logger = logging.getLogger(__name__)


class TranslationService:
    def __init__(self, whisper_model_size: str = "base"):
        logger.info("=" * 60)
        logger.info("🌐 Initializing Translation Service")
        logger.info(f"📦 Whisper model: {whisper_model_size}")
        logger.info("=" * 60)

        device = "cuda" if torch.cuda.is_available() else "cpu"
        logger.info(f"🖥️  Device: {device.upper()}")

        logger.info("⏳ Loading Whisper model...")
        self.whisper_model = whisper.load_model(whisper_model_size, device=device)
        logger.info("✅ Whisper model loaded")

        try:
            from deep_translator import GoogleTranslator
            self._translator_class = GoogleTranslator
            test = GoogleTranslator(source="en", target="si").translate("hello")
            logger.info(f"✅ deep-translator ready (test en→si: '{test}')")
        except ImportError:
            self._translator_class = None
            logger.warning("⚠️  deep-translator not installed. Run: pip install deep-translator")
        except Exception as e:
            self._translator_class = None
            logger.warning(f"⚠️  deep-translator test failed: {e}")

        logger.info("✅ Translation Service ready")
        logger.info("=" * 60)

    def transcribe_and_translate(self, audio_path: str, target_language: str = "si") -> dict:
        result = {
            "transcribed_text": None,
            "detected_language": None,
            "is_already_target": False,
            "translated_text": None,
            "target_language": target_language,
            "translation_error": None,
        }

        # Step 1: Transcribe with Whisper
        try:
            logger.info(f"🎙️  Transcribing: {os.path.basename(audio_path)}")
            whisper_result = self.whisper_model.transcribe(
                audio_path, fp16=torch.cuda.is_available()
            )
            transcribed_text = whisper_result.get("text", "").strip()
            detected_lang    = whisper_result.get("language", "unknown")

            result["transcribed_text"] = transcribed_text
            result["detected_language"] = detected_lang

            logger.info(f"📝 Transcription : '{transcribed_text}'")
            logger.info(f"🌍 Detected lang : {detected_lang}")
            logger.info(f"🎯 Target lang   : {target_language}")

            if not transcribed_text:
                logger.warning("⚠️  Empty transcription – skipping translation")
                return result

        except Exception as e:
            logger.error(f"❌ Whisper transcription failed: {e}")
            result["translation_error"] = f"Transcription failed: {str(e)}"
            return result

        # Step 2: Check if already in target language
        detected_norm = detected_lang.lower().split("-")[0]
        target_norm   = target_language.lower().split("-")[0]

        if detected_norm == target_norm:
            logger.info(f"✅ Already in target language '{target_language}' – passing through")
            result["is_already_target"] = True
            result["translated_text"]   = transcribed_text
            return result

        # Step 3: Translate
        if self._translator_class is None:
            result["translation_error"] = "deep-translator library not available"
            return result

        try:
            logger.info(f"🔄 Translating '{detected_lang}' → '{target_language}'...")
            translator = self._translator_class(source=detected_lang, target=target_language)
            translated = translator.translate(transcribed_text)
            result["translated_text"] = translated
            logger.info(f"✅ Translation: '{translated}'")
        except Exception as e:
            logger.error(f"❌ Translation failed: {e}")
            try:
                logger.info("🔄 Retrying with source='auto'...")
                translator = self._translator_class(source="auto", target=target_language)
                translated = translator.translate(transcribed_text)
                result["translated_text"] = translated
                logger.info(f"✅ Fallback translation: '{translated}'")
            except Exception as e2:
                logger.error(f"❌ Fallback also failed: {e2}")
                result["translation_error"] = f"Translation failed: {str(e2)}"

        return result