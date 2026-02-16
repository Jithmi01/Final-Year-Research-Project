# FILE: Backend/utils/audio_processor.py
"""
Audio Preprocessing and Enhancement Module
Handles audio loading, noise reduction, normalization, and validation
"""

import librosa
import numpy as np
import soundfile as sf
import noisereduce as nr
import logging
import os
from pathlib import Path

logger = logging.getLogger(__name__)


class AudioProcessor:
    """
    Audio preprocessing pipeline for voice recognition
    Improves audio quality and consistency for better recognition accuracy
    """
    
    def __init__(self, target_sr=16000):
        """
        Initialize audio processor
        
        Args:
            target_sr: Target sampling rate in Hz (16kHz optimal for voice)
        """
        self.target_sr = target_sr
        logger.info(f"🎵 Audio Processor initialized | Target SR: {target_sr}Hz")
    
    def load_audio(self, file_path):
        """Load audio file and resample to target rate"""
        try:
            audio, sr = librosa.load(file_path, sr=self.target_sr, mono=True)
            duration = len(audio) / sr
            logger.info(f"✅ Audio loaded: {Path(file_path).name} | Duration: {duration:.2f}s")
            return audio, sr
        except Exception as e:
            logger.error(f"❌ Failed to load audio file: {e}")
            raise RuntimeError(f"Audio loading failed: {str(e)}")
    
    def reduce_noise(self, audio, sr, noise_reduction_strength=0.8):
        """Remove background noise using spectral gating"""
        try:
            logger.info("🔇 Applying noise reduction...")
            reduced_audio = nr.reduce_noise(
                y=audio,
                sr=sr,
                stationary=True,
                prop_decrease=noise_reduction_strength
            )
            logger.info("✅ Noise reduction applied")
            return reduced_audio
        except Exception as e:
            logger.warning(f"⚠️  Noise reduction failed, using original audio: {e}")
            return audio
    
    def normalize_audio(self, audio, target_level=0.9):
        """Normalize audio amplitude to target level"""
        current_peak = np.abs(audio).max()
        
        if current_peak > 0:
            norm_factor = target_level / current_peak
            normalized = audio * norm_factor
            logger.info(f"✅ Audio normalized | Peak: {current_peak:.3f} → {target_level}")
        else:
            logger.warning("⚠️  Audio is silent, skipping normalization")
            normalized = audio
        
        return normalized
    
    def trim_silence(self, audio, sr, top_db=20):
        """Remove silence from beginning and end of audio"""
        try:
            trimmed, _ = librosa.effects.trim(audio, top_db=top_db)
            logger.info(f"✅ Silence trimmed | Length: {len(trimmed)/sr:.2f}s")
            return trimmed
        except Exception as e:
            logger.warning(f"⚠️  Silence trimming failed: {e}")
            return audio
    
    def preprocess(
        self,
        file_path,
        apply_noise_reduction=True,
        apply_normalization=True,
        apply_trimming=True,
        noise_strength=0.8
    ):
        """
        Complete preprocessing pipeline
        
        Returns:
            tuple: (processed_audio, sample_rate)
        """
        logger.info(f"🔄 AUDIO PREPROCESSING: {Path(file_path).name}")
        
        # Load audio
        audio, sr = self.load_audio(file_path)
        
        # Remove DC offset
        audio = audio - np.mean(audio)
        
        # Noise reduction
        if apply_noise_reduction:
            audio = self.reduce_noise(audio, sr, noise_strength)
        
        # Trim silence
        if apply_trimming:
            audio = self.trim_silence(audio, sr)
        
        # Normalize
        if apply_normalization:
            audio = self.normalize_audio(audio)
        
        logger.info(f"✅ Preprocessing completed | Final length: {len(audio)/sr:.2f}s")
        
        return audio, sr
    
    def save_audio(self, audio, sr, output_path):
        """Save processed audio to file"""
        try:
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            sf.write(output_path, audio, sr)
            logger.info(f"✅ Audio saved: {Path(output_path).name}")
        except Exception as e:
            logger.error(f"❌ Failed to save audio: {e}")
            raise RuntimeError(f"Audio saving failed: {str(e)}")
    
    def validate_audio(self, file_path, min_duration=2, max_duration=30):
        """
        Validate audio file for voice recognition
        
        Returns:
            dict: Validation result
        """
        logger.info(f"🔍 Validating audio: {Path(file_path).name}")
        
        try:
            if not os.path.exists(file_path):
                return {"valid": False, "error": "Audio file not found"}
            
            # Check file size
            file_size = os.path.getsize(file_path)
            if file_size > 16 * 1024 * 1024:
                return {
                    "valid": False,
                    "error": f"File too large ({file_size / 1024 / 1024:.1f}MB). Max: 16MB"
                }
            
            # Load and check duration
            audio, sr = self.load_audio(file_path)
            duration = len(audio) / sr
            
            if duration < min_duration:
                return {
                    "valid": False,
                    "error": f"Audio too short ({duration:.1f}s). Minimum: {min_duration}s",
                    "duration": duration
                }
            
            if duration > max_duration:
                return {
                    "valid": False,
                    "error": f"Audio too long ({duration:.1f}s). Maximum: {max_duration}s",
                    "duration": duration
                }
            
            # Check if audio is silent
            if np.abs(audio).max() < 0.001:
                return {
                    "valid": False,
                    "error": "Audio appears to be silent or too quiet"
                }
            
            logger.info(f"✅ Audio validation passed | Duration: {duration:.1f}s")
            
            return {
                "valid": True,
                "duration": duration,
                "sample_rate": sr,
                "num_samples": len(audio)
            }
            
        except Exception as e:
            logger.error(f"❌ Audio validation failed: {e}")
            return {
                "valid": False,
                "error": f"Validation error: {str(e)}"
            }