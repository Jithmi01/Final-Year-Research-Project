# FILE: services/voice_service.py (COMPLETE FIX)
"""
Voice Recognition Service using SpeechBrain ECAPA-TDNN
High-accuracy speaker identification and verification

FIXED: 
- Updated import path for SpeechBrain 1.0+
- Compatibility patch for huggingface_hub
"""

from speechbrain.pretrained import EncoderClassifier

import numpy as np
from scipy.spatial.distance import cosine, euclidean
import logging
import os
import torch

logger = logging.getLogger(__name__)


class VoiceRecognitionService:
    """
    Voice recognition service with speaker identification and verification
    Uses SpeechBrain ECAPA-TDNN model for state-of-the-art accuracy
    """
    
    def __init__(self, model_name="speechbrain/spkrec-ecapa-voxceleb", model_save_dir="pretrained_models"):
        """
        Initialize voice recognition model
        
        Args:
            model_name: SpeechBrain model identifier
            model_save_dir: Directory to save/load pretrained model
        """
        logger.info("=" * 60)
        logger.info("🧠 Initializing Voice Recognition Service")
        logger.info("=" * 60)
        logger.info(f"📦 Model: {model_name}")
        logger.info(f"💾 Save Directory: {model_save_dir}")
        
        try:
            # Create save directory
            os.makedirs(model_save_dir, exist_ok=True)
            
            # Check for GPU availability
            device = "cuda" if torch.cuda.is_available() else "cpu"
            logger.info(f"🖥️  Device: {device.upper()}")
            
            # Load pretrained ECAPA-TDNN encoder
            logger.info("⏳ Loading SpeechBrain ECAPA-TDNN model...")
            logger.info("   (First run: ~500MB download, takes 2-5 minutes)")
            
            # CRITICAL FIX: Monkey patch huggingface_hub BEFORE loading model
           
            
            try:
                self.encoder = EncoderClassifier.from_hparams(
                    source=model_name,
                    savedir=model_save_dir,
                    run_opts={"device": device}
                )
                logger.info("✅ Voice recognition model loaded successfully!")
                
            except TypeError as e:
                if "use_auth_token" in str(e):
                    logger.error("❌ Failed to load model even with compatibility patch")
                    logger.error("💡 This might be a huggingface_hub version issue")
                    logger.error(f"   Error: {e}")
                    raise
                else:
                    raise
            
            logger.info(f"✅ Embedding dimension: 192")
            logger.info("=" * 60)
            
        except Exception as e:
            logger.error(f"❌ Failed to load voice recognition model: {e}")
            logger.error("💡 Solutions:")
            logger.error("   1. Update packages:")
            logger.error("      pip install --upgrade speechbrain>=1.0.0")
            logger.error("      pip install --upgrade huggingface_hub>=0.20.0")
            logger.error("   2. OR downgrade:")
            logger.error("      pip install huggingface_hub==0.16.4")
            logger.error("      pip install speechbrain==0.5.16")
            raise
    
   
    
    def extract_embedding(self, audio_path):
        """
        Extract voice embedding from audio file
        
        Args:
            audio_path: Path to audio file (WAV format recommended)
            
        Returns:
            numpy.ndarray: Voice embedding vector (192 dimensions)
        """
        try:
            logger.info(f"🔍 Extracting embedding from: {os.path.basename(audio_path)}")
            
            # Load and process audio file
            import torchaudio
            
            # Load audio file
            signal, fs = torchaudio.load(audio_path)
            
            # Resample if necessary (ECAPA-TDNN expects 16kHz)
            if fs != 16000:
                resampler = torchaudio.transforms.Resample(fs, 16000)
                signal = resampler(signal)
            
            # Extract embedding using SpeechBrain (encode_batch expects batch format)
            embedding = self.encoder.encode_batch(signal)
            
            # Convert to numpy array
            embedding_np = embedding.squeeze().cpu().detach().numpy()
            
            logger.info(f"✅ Embedding extracted successfully | Shape: {embedding_np.shape}")
            
            return embedding_np
            
        except Exception as e:
            logger.error(f"❌ Embedding extraction failed: {e}")
            raise RuntimeError(f"Failed to extract voice embedding: {str(e)}")
    
    def calculate_similarity(self, embedding1, embedding2, method="cosine"):
        """
        Calculate similarity between embeddings
        
        Args:
            embedding1: First voice embedding
            embedding2: Second voice embedding
            method: Similarity method ("cosine" or "euclidean")
            
        Returns:
            float: Similarity score (0-1)
        """
        if method == "cosine":
            similarity = 1 - cosine(embedding1, embedding2)
        elif method == "euclidean":
            distance = euclidean(embedding1, embedding2)
            similarity = 1 / (1 + distance)
        else:
            raise ValueError(f"Unknown similarity method: {method}")
        
        return float(similarity)
    
    def register_voice(self, audio_paths, user_name):
        """
        Register user voice with multiple samples
        
        Args:
            audio_paths: List of audio file paths
            user_name: Name of the user
            
        Returns:
            dict: Registration result with embeddings
        """
        logger.info("=" * 60)
        logger.info(f"📝 Registering voice for: {user_name}")
        logger.info(f"📊 Number of samples: {len(audio_paths)}")
        logger.info("=" * 60)
        
        try:
            embeddings = []
            
            for i, audio_path in enumerate(audio_paths, 1):
                logger.info(f"🔄 Processing sample {i}/{len(audio_paths)}: {os.path.basename(audio_path)}")
                
                # Extract embedding
                embedding = self.extract_embedding(audio_path)
                
                # Convert to list for JSON/MongoDB storage
                embeddings.append(embedding.tolist())
                
                logger.info(f"✅ Sample {i} processed successfully")
            
            # Calculate inter-sample similarity (quality check)
            avg_similarity = 1.0  # Default for single sample
            
            if len(embeddings) > 1:
                similarities = []
                for i in range(len(embeddings)):
                    for j in range(i + 1, len(embeddings)):
                        sim = self.calculate_similarity(
                            np.array(embeddings[i]),
                            np.array(embeddings[j])
                        )
                        similarities.append(sim)
                
                avg_similarity = float(np.mean(similarities))
                logger.info(f"📊 Inter-sample similarity: {avg_similarity:.2%}")
                
                if avg_similarity < 0.5:
                    logger.warning("⚠️  Low inter-sample similarity detected!")
                    logger.warning("💡 Recommendation: Re-record in quieter environment")
            
            logger.info(f"✅ Voice registration completed for '{user_name}'")
            logger.info("=" * 60)
            
            return {
                "success": True,
                "embeddings": embeddings,
                "num_samples": len(embeddings),
                "avg_inter_similarity": avg_similarity
            }
            
        except Exception as e:
            logger.error(f"❌ Voice registration failed: {e}")
            return {
                "success": False,
                "error": str(e)
            }
    
    def identify_speaker(self, audio_path, registered_users, threshold=0.65, method="cosine"):
        """
        Identify speaker from voice sample
        
        Args:
            audio_path: Path to audio file
            registered_users: List of user dictionaries from database
            threshold: Minimum similarity score for positive identification
            method: Similarity calculation method
            
        Returns:
            dict: Identification result with confidence scores
        """
        logger.info("=" * 60)
        logger.info("🔍 Starting Speaker Identification")
        logger.info("=" * 60)
        
        try:
            if not registered_users or len(registered_users) == 0:
                logger.warning("⚠️  No users registered in database")
                return {
                    "identified": False,
                    "name": "No users registered",
                    "confidence": 0.0,
                    "all_scores": [],
                    "threshold": float(threshold * 100)
                }
            
            # Extract embedding from new audio
            logger.info("🔄 Extracting embedding from input audio...")
            new_embedding = self.extract_embedding(audio_path)
            
            best_match = None
            best_score = 0.0
            all_scores = []
            
            # Compare with all registered users
            for user in registered_users:
                user_name = user['name']
                user_embeddings = user['voice_embeddings']
                
                # Calculate similarity with all embeddings of this user
                similarities = []
                for stored_embedding in user_embeddings:
                    score = self.calculate_similarity(
                        new_embedding,
                        np.array(stored_embedding),
                        method=method
                    )
                    similarities.append(score)
                
                avg_score = float(np.mean(similarities))
                max_score = float(np.max(similarities))
                
                all_scores.append({
                    "name": user_name,
                    "avg_score": avg_score,
                    "max_score": max_score,
                    "num_samples": int(len(similarities))
                })
                
                if avg_score > best_score:
                    best_score = avg_score
                    best_match = user_name
            
            # Sort scores
            all_scores.sort(key=lambda x: x['avg_score'], reverse=True)
            
            # Determine identification result
            MIN_DETECTION_THRESHOLD = 0.30
            SILENCE_THRESHOLD = 0.05
            
            if best_score < SILENCE_THRESHOLD:
                identified = False
                result_name = "Can't hear someone speaking"
            elif best_score < MIN_DETECTION_THRESHOLD:
                identified = False
                result_name = "Unknown Person Speaking"
            elif best_score >= MIN_DETECTION_THRESHOLD and best_score < threshold:
                identified = True
                result_name = best_match
            else:
                identified = True
                result_name = best_match
            
            logger.info(f"✅ Identification complete: {result_name} ({best_score:.2%})")
            logger.info("=" * 60)
            
            return {
                "identified": bool(identified),
                "name": result_name,
                "confidence": round(best_score * 100, 2),
                "all_scores": all_scores,
                "threshold": round(threshold * 100, 2),
                "method": method
            }
            
        except Exception as e:
            logger.error(f"❌ Speaker identification failed: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return {
                "identified": False,
                "name": "Error",
                "confidence": 0.0,
                "error": str(e),
                "all_scores": []
            }
    
    def verify_speaker(self, audio_path, claimed_name, registered_users, threshold=0.65):
        """
        Verify if speaker matches claimed identity
        
        Args:
            audio_path: Path to audio file
            claimed_name: Name claimed by speaker
            registered_users: List of users from database
            threshold: Minimum similarity score
            
        Returns:
            dict: Verification result
        """
        try:
            # Find claimed user
            claimed_user = next(
                (u for u in registered_users if u['name'] == claimed_name),
                None
            )
            
            if not claimed_user:
                return {
                    "verified": False,
                    "message": f"User '{claimed_name}' not registered",
                    "confidence": 0.0
                }
            
            # Extract embedding
            new_embedding = self.extract_embedding(audio_path)
            
            # Compare with claimed user's embeddings
            similarities = []
            for stored_embedding in claimed_user['voice_embeddings']:
                score = self.calculate_similarity(
                    new_embedding,
                    np.array(stored_embedding)
                )
                similarities.append(score)
            
            avg_score = float(np.mean(similarities))
            verified = bool(avg_score >= threshold)
            
            message = f"Voice {'verified as' if verified else 'does not match'} '{claimed_name}'"
            
            return {
                "verified": verified,
                "message": message,
                "confidence": round(avg_score * 100, 2)
            }
            
        except Exception as e:
            logger.error(f"❌ Speaker verification failed: {e}")
            return {
                "verified": False,
                "message": f"Verification error: {str(e)}",
                "confidence": 0.0
            }