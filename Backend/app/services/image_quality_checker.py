# ============================================================================
# FILE: app/services/image_quality_checker.py (ENHANCED VERSION)
# Image quality + Bill detection for visually impaired users
# ============================================================================

import cv2
import numpy as np
from typing import Dict, List, Tuple
from dataclasses import dataclass
from app.services.bill_detector import detect_bill_position


# Add right after imports
print("[STARTUP] Attempting to import bill_detector...")
try:
    from app.services.bill_detector import detect_bill_position
    print("[STARTUP] ✓ Bill detector imported successfully")
except Exception as e:
    print(f"[STARTUP] ✗ FAILED to import bill detector: {e}")
    import traceback
    traceback.print_exc()
    

@dataclass
class QualityIssue:
    """Represents an image quality issue"""
    type: str
    severity: str
    message: str
    voice_prompt: str
    score: float

class ImageQualityChecker:
    """
    Analyzes image quality AND bill positioning
    Provides comprehensive guidance for visually impaired users
    """
    
    # Quality thresholds
    MIN_BRIGHTNESS = 40
    MAX_BRIGHTNESS = 220
    OPTIMAL_BRIGHTNESS = 120
    
    MIN_SHARPNESS = 100
    OPTIMAL_SHARPNESS = 300
    
    MIN_CONTRAST = 30
    OPTIMAL_CONTRAST = 60
    
    def __init__(self):
        """Initialize quality checker"""
        self.last_check_time = 0
        self.check_interval = 0.5
    
    def analyze_image(self, image_bytes: bytes) -> Dict:
        """
        Analyze image quality AND bill positioning
        
        Returns comprehensive guidance for visually impaired users
        """
        # Decode image
        nparr = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            return self._create_error_result("Cannot read image")
        
        # STEP 1: Check basic image quality FIRST (brightness, blur, contrast)
        quality_issues = []
        
        brightness_issue = self._check_brightness(image)
        if brightness_issue:
            quality_issues.append(brightness_issue)
        
        blur_issue = self._check_sharpness(image)
        if blur_issue:
            quality_issues.append(blur_issue)
        
        contrast_issue = self._check_contrast(image)
        if contrast_issue:
            quality_issues.append(contrast_issue)
        
        # Calculate base quality score
        quality_score = self._calculate_quality_score(quality_issues)
        
        # Check if basic quality is acceptable
        has_critical_quality_issue = any(
            issue.severity == 'critical' for issue in quality_issues
        )
        
        # STEP 2: Detect bill position (only if basic quality is OK)
        try:
            print("[QUALITY] Calling bill detector...")
            bill_detection = detect_bill_position(image_bytes)
            print(f"[QUALITY] Bill detection result: {bill_detection.get('bill_detected', False)}")
        except Exception as e:
            print(f"[QUALITY ERROR] Bill detection failed: {e}")
            import traceback
            traceback.print_exc()
            # Fallback - assume no bill detected
            bill_detection = {
                'bill_detected': False,
                'guidance': 'Hold bill in front of camera',
                'direction': 'none',
                'is_centered': False,
                'is_correct_size': False,
                'is_level': False,
                'ready_to_scan': False
            }
        
        # PRIORITY SYSTEM:
        # 1. Critical quality issues (too dark, very blurry) - fix these first
        # 2. Bill detection (is there a bill?)
        # 3. Bill positioning (center it)
        # 4. Minor quality issues
        
        # If CRITICAL quality problem, report that first
        if has_critical_quality_issue:
            primary_issue = self._get_primary_issue(quality_issues)
            return {
                'quality_score': quality_score,
                'issues': quality_issues,
                'is_acceptable': False,
                'primary_issue': 'critical_quality',
                'voice_prompt': primary_issue.voice_prompt if primary_issue else "Fix lighting and hold steady",
                'recommendations': [i.message for i in quality_issues],
                'brightness_ok': brightness_issue is None or brightness_issue.severity != 'critical',
                'sharpness_ok': blur_issue is None or blur_issue.severity != 'critical',
                'size_ok': False,
                'contrast_ok': contrast_issue is None or contrast_issue.severity != 'critical',
                'bill_detected': False,
                'bill_centered': False,
                'bill_correct_size': False,
                'bill_level': False,
                'ready_to_scan': False,
                'direction': 'none'
            }
        
        # Quality is acceptable, now check bill
        if not bill_detection['bill_detected']:
            # No bill detected
            return {
                'quality_score': quality_score * 0.5,
                'issues': quality_issues,
                'is_acceptable': False,
                'primary_issue': 'no_bill',
                'voice_prompt': bill_detection['guidance'],
                'recommendations': [bill_detection['guidance']] + [i.message for i in quality_issues],
                'brightness_ok': brightness_issue is None or brightness_issue.severity != 'critical',
                'sharpness_ok': blur_issue is None or blur_issue.severity != 'critical',
                'size_ok': False,
                'contrast_ok': contrast_issue is None or contrast_issue.severity != 'critical',
                'bill_detected': False,
                'bill_centered': False,
                'bill_correct_size': False,
                'bill_level': False,
                'ready_to_scan': False,
                'direction': bill_detection['direction']
            }
        
        # Bill detected but not positioned correctly
        if not bill_detection['ready_to_scan']:
            return {
                'quality_score': quality_score * 0.8,
                'issues': quality_issues,
                'is_acceptable': False,
                'primary_issue': 'bill_positioning',
                'voice_prompt': bill_detection['guidance'],
                'recommendations': [bill_detection['guidance']],
                'brightness_ok': brightness_issue is None or brightness_issue.severity != 'critical',
                'sharpness_ok': blur_issue is None or blur_issue.severity != 'critical',
                'size_ok': bill_detection['is_correct_size'],
                'contrast_ok': contrast_issue is None or contrast_issue.severity != 'critical',
                'bill_detected': True,
                'bill_centered': bill_detection['is_centered'],
                'bill_correct_size': bill_detection['is_correct_size'],
                'bill_level': bill_detection['is_level'],
                'ready_to_scan': False,
                'direction': bill_detection['direction']
            }
        
        # Bill is perfectly positioned - final quality check
        if quality_issues:
            # Has minor quality issues
            primary_issue = self._get_primary_issue(quality_issues)
            return {
                'quality_score': quality_score,
                'issues': quality_issues,
                'is_acceptable': quality_score >= 70,  # More lenient when bill is positioned
                'primary_issue': 'minor_quality' if quality_score >= 70 else 'image_quality',
                'voice_prompt': 'Bill centered. Ready to scan.' if quality_score >= 70 else primary_issue.voice_prompt,
                'recommendations': [i.message for i in quality_issues] if quality_score < 70 else [],
                'brightness_ok': brightness_issue is None,
                'sharpness_ok': blur_issue is None,
                'size_ok': True,
                'contrast_ok': contrast_issue is None,
                'bill_detected': True,
                'bill_centered': True,
                'bill_correct_size': True,
                'bill_level': True,
                'ready_to_scan': quality_score >= 70,
                'direction': 'center'
            }
        
        # PERFECT! Bill positioned AND quality excellent
        return {
            'quality_score': quality_score,
            'issues': [],
            'is_acceptable': True,
            'primary_issue': None,
            'voice_prompt': 'Perfect. Ready to scan.',
            'recommendations': [],
            'brightness_ok': True,
            'sharpness_ok': True,
            'size_ok': True,
            'contrast_ok': True,
            'bill_detected': True,
            'bill_centered': True,
            'bill_correct_size': True,
            'bill_level': True,
            'ready_to_scan': True,
            'direction': 'center'
        }
    
    def _check_brightness(self, image: np.ndarray) -> QualityIssue:
        """Check if image is too dark or too bright"""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        brightness = np.mean(gray)
        
        print(f"[QUALITY] Brightness: {brightness:.1f}")
        
        if brightness < self.MIN_BRIGHTNESS:
            severity = 'critical' if brightness < 30 else 'warning'
            return QualityIssue(
                type='dark',
                severity=severity,
                message=f'Image too dark (brightness: {brightness:.0f})',
                voice_prompt='Too dark. Move to brighter area.',
                score=max(0, (brightness / self.MIN_BRIGHTNESS) * 50)
            )
        
        elif brightness > self.MAX_BRIGHTNESS:
            severity = 'critical' if brightness > 240 else 'warning'
            return QualityIssue(
                type='bright',
                severity=severity,
                message=f'Image too bright (brightness: {brightness:.0f})',
                voice_prompt='Too bright. Reduce lighting.',
                score=max(0, 100 - ((brightness - self.MAX_BRIGHTNESS) / 35) * 50)
            )
        
        return None
    
    def _check_sharpness(self, image: np.ndarray) -> QualityIssue:
        """Check if image is blurry"""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        laplacian = cv2.Laplacian(gray, cv2.CV_64F)
        sharpness = laplacian.var()
        
        print(f"[QUALITY] Sharpness: {sharpness:.1f}")
        
        if sharpness < self.MIN_SHARPNESS:
            severity = 'critical' if sharpness < 50 else 'warning'
            return QualityIssue(
                type='blur',
                severity=severity,
                message=f'Image is blurry (sharpness: {sharpness:.0f})',
                voice_prompt='Hold steady. Image is blurry.',
                score=max(0, (sharpness / self.MIN_SHARPNESS) * 50)
            )
        
        return None
    
    def _check_contrast(self, image: np.ndarray) -> QualityIssue:
        """Check if image has good contrast"""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        contrast = np.std(gray)
        
        print(f"[QUALITY] Contrast: {contrast:.1f}")
        
        if contrast < self.MIN_CONTRAST:
            severity = 'warning'
            return QualityIssue(
                type='contrast',
                severity=severity,
                message=f'Low contrast ({contrast:.0f})',
                voice_prompt='Adjust lighting for better contrast.',
                score=max(0, (contrast / self.MIN_CONTRAST) * 60)
            )
        
        return None
    
    def _calculate_quality_score(self, issues: List[QualityIssue]) -> float:
        """Calculate overall quality score"""
        if not issues:
            return 95.0
        
        score = 100.0
        for issue in issues:
            if issue.severity == 'critical':
                score -= 30
            elif issue.severity == 'warning':
                score -= 15
        
        return max(0, min(100, score))
    
    def _get_primary_issue(self, issues: List[QualityIssue]) -> QualityIssue:
        """Get the most important issue to address"""
        if not issues:
            return None
        
        critical = [i for i in issues if i.severity == 'critical']
        if critical:
            return critical[0]
        
        warnings = [i for i in issues if i.severity == 'warning']
        if warnings:
            return warnings[0]
        
        return issues[0]
    
    def _create_error_result(self, error_msg: str) -> Dict:
        """Create error result"""
        return {
            'quality_score': 0,
            'issues': [],
            'is_acceptable': False,
            'primary_issue': 'error',
            'voice_prompt': 'Cannot analyze image. Try again.',
            'recommendations': [error_msg],
            'brightness_ok': False,
            'sharpness_ok': False,
            'size_ok': False,
            'contrast_ok': False,
            'bill_detected': False,
            'bill_centered': False,
            'bill_correct_size': False,
            'bill_level': False,
            'ready_to_scan': False,
            'direction': 'none'
        }


# Singleton instance
_quality_checker = None

def get_quality_checker():
    """Get quality checker instance"""
    global _quality_checker
    if _quality_checker is None:
        _quality_checker = ImageQualityChecker()
    return _quality_checker


def check_image_quality(image_bytes: bytes) -> Dict:
    """Main function to check image quality with bill detection"""
    checker = get_quality_checker()
    return checker.analyze_image(image_bytes)