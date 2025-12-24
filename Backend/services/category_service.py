# ============================================================================
# FILE: app/services/category_service.py
# Smart category detection for expenses
# ============================================================================

"""
Category Detection Service
Intelligent expense categorization based on vendor names and items
"""

from typing import Tuple, List

# ============================================================================
# CATEGORY DEFINITIONS
# ============================================================================

CATEGORY_KEYWORDS = {
    'Health': {
        'vendor_keywords': [
            'pharmacy', 'pharma', 'medical', 'clinic', 'hospital', 'healthcare',
            'drug', 'medicine', 'chemist', 'apothecary', 'osusala', 'medicare',
            'wellness', 'dental', 'optical', 'care plus', 'healthguard', 'medi',
            'doctor', 'dispensary', 'lab', 'laboratory'
        ],
        'item_keywords': [
            'tablet', 'capsule', 'syrup', 'injection', 'medicine', 'drug',
            'antibiotic', 'paracetamol', 'vitamin', 'supplement', 'cream',
            'ointment', 'bandage', 'gauze', 'thermometer', 'mask', 'sanitizer',
            'pills', 'prescription', 'medical'
        ],
        'priority': 10
    },
    
    'Grocery': {
        'vendor_keywords': [
            'supermarket', 'super', 'mart', 'grocery', 'food', 'keells',
            'cargills', 'arpico', 'laugfs', 'shop', 'store', 'market',
            'fresh', 'organic', 'vegetable', 'fruit', 'mini', 'convenience'
        ],
        'item_keywords': [
            'rice', 'bread', 'milk', 'egg', 'flour', 'sugar', 'salt', 'oil',
            'vegetable', 'fruit', 'meat', 'chicken', 'fish', 'butter', 'cheese',
            'yogurt', 'juice', 'water', 'tea', 'coffee', 'biscuit', 'pasta',
            'noodles', 'sauce', 'spice', 'dhal', 'beans', 'onion', 'potato',
            'tomato', 'carrot', 'cereal', 'snack'
        ],
        'priority': 7
    },
    
    'Dining': {
        'vendor_keywords': [
            'restaurant', 'restauraht', 'cafe', 'coffee', 'hotel', 'bistro', 
            'eatery', 'pizza', 'burger', 'kfc', 'mcdonalds', "mcdonald's", 
            'subway', 'dining', 'grill', 'kitchen', 'cuisine', 'food court', 
            'bakery', 'pastry', 'diner', 'buffet', 'bar', 'pub', 'columbus',
            'tavern', 'steakhouse', 'inn', 'chopstix', 'rice', 'noodle house',
            'brew', 'barista'
        ],
        'item_keywords': [
            'pizza', 'burger', 'sandwich', 'pasta', 'fried rice', 'noodles',
            'curry', 'kottu', 'hoppers', 'roti', 'biryani', 'dessert',
            'ice cream', 'cake', 'coffee', 'latte', 'cappuccino', 'espresso',
            'soft drink', 'soda', 'juice', 'meal', 'lunch', 'dinner', 'breakfast'
        ],
        'priority': 8
    },
    
    'Transport': {
        'vendor_keywords': [
            'taxi', 'uber', 'pickme', 'cab', 'transport', 'bus', 'train',
            'rail', 'fuel', 'petrol', 'diesel', 'gas', 'station', 'ceypetco',
            'ioc', 'parking', 'toll', 'highway', 'metro', 'shuttle'
        ],
        'item_keywords': [
            'petrol', 'diesel', 'fuel', 'ride', 'trip', 'fare', 'toll',
            'parking', 'highway', 'octane', 'gas', 'ticket', 'pass'
        ],
        'priority': 9
    },
    
    'Utilities': {
        'vendor_keywords': [
            'electricity', 'water', 'ceb', 'leco', 'utility', 'bill payment',
            'telephone', 'mobile', 'internet', 'wifi', 'broadband', 'dialog',
            'mobitel', 'airtel', 'hutch', 'telecom', 'connection'
        ],
        'item_keywords': [
            'electricity', 'power', 'water', 'phone', 'mobile', 'data',
            'internet', 'broadband', 'recharge', 'bill', 'connection fee'
        ],
        'priority': 9
    },
    
    'Shopping': {
        'vendor_keywords': [
            'fashion', 'clothing', 'apparels', 'boutique', 'outlet', 'mall',
            'department', 'textile', 'garment', 'shoe', 'footwear', 'accessories',
            'jewelry', 'jewellery', 'electronics', 'mobile', 'samsung', 'apple',
            'singer', 'abans', 'softlogic', 'warehouse', 'retail'
        ],
        'item_keywords': [
            'shirt', 'pant', 'dress', 'shoe', 'bag', 'watch', 'phone',
            'laptop', 'tv', 'iron', 'fan', 'fridge', 'washing machine',
            'electronics', 'gadget', 'accessory', 'clothing', 'jeans'
        ],
        'priority': 6
    },
    
    'Entertainment': {
        'vendor_keywords': [
            'cinema', 'theatre', 'movie', 'pvr', 'scope', 'entertainment',
            'park', 'zoo', 'museum', 'gallery', 'ticket', 'show', 'concert',
            'event', 'gaming', 'arcade', 'bowling', 'playstation', 'fun'
        ],
        'item_keywords': [
            'ticket', 'movie', 'film', 'show', 'entry', 'admission',
            'game', 'popcorn', 'snack', 'event', 'concert'
        ],
        'priority': 5
    },
    
    'Education': {
        'vendor_keywords': [
            'school', 'university', 'college', 'institute', 'academy',
            'education', 'learning', 'class', 'tuition', 'course',
            'bookshop', 'stationery', 'library', 'campus'
        ],
        'item_keywords': [
            'book', 'notebook', 'pen', 'pencil', 'paper', 'textbook',
            'stationery', 'tuition', 'fee', 'course', 'class fee'
        ],
        'priority': 8
    },
    
    'Personal Care': {
        'vendor_keywords': [
            'salon', 'spa', 'beauty', 'parlour', 'barber', 'hair',
            'cosmetic', 'skincare', 'nail', 'wellness'
        ],
        'item_keywords': [
            'haircut', 'shampoo', 'soap', 'lotion', 'cream', 'perfume',
            'deodorant', 'toothpaste', 'brush', 'razor', 'facial', 'massage',
            'manicure', 'pedicure', 'wax', 'treatment'
        ],
        'priority': 6
    },
    
    'Home & Garden': {
        'vendor_keywords': [
            'hardware', 'home', 'garden', 'furniture', 'decor', 'paint',
            'tools', 'building', 'construction', 'homeware'
        ],
        'item_keywords': [
            'paint', 'brush', 'cement', 'wood', 'nail', 'screw', 'hammer',
            'furniture', 'chair', 'table', 'curtain', 'bulb', 'pipe', 'tap',
            'tool', 'drill'
        ],
        'priority': 5
    }
}

DEFAULT_CATEGORY = 'General'

# ============================================================================
# CATEGORY DETECTOR
# ============================================================================

class CategoryDetector:
    """Intelligent category detection"""
    
    @staticmethod
    def detect(vendor_name: str, items: List[str], full_text: str) -> str:
        """
        Detect expense category using multiple sources
        
        Priority: vendor name > items > full text
        
        Args:
            vendor_name: Store/vendor name
            items: List of purchased items
            full_text: Complete bill text
        
        Returns:
            Category name
        """
        print(f"[CATEGORY] Detecting for vendor: {vendor_name}")
        
        # Priority 1: Vendor name (most reliable)
        if vendor_name and vendor_name != 'Unknown':
            category, confidence = CategoryDetector._from_vendor(vendor_name)
            print(f"  Vendor analysis → {category} (confidence: {confidence}/10)")
            
            if confidence >= 7:
                print(f"[CATEGORY] ✓ High confidence from vendor: {category}")
                return category
        
        # Priority 2: Items list
        if items:
            category, confidence = CategoryDetector._from_items(items)
            print(f"  Items analysis → {category} (confidence: {confidence}/10)")
            
            if confidence >= 5:
                print(f"[CATEGORY] ✓ Good confidence from items: {category}")
                return category
        
        # Priority 3: Full text
        if full_text:
            category, confidence = CategoryDetector._from_text(full_text)
            print(f"  Text analysis → {category} (confidence: {confidence}/10)")
            
            if confidence >= 3:
                print(f"[CATEGORY] ✓ Text match: {category}")
                return category
        
        print(f"[CATEGORY] ⚠️  Using default: {DEFAULT_CATEGORY}")
        return DEFAULT_CATEGORY
    
    @staticmethod
    def _from_vendor(vendor_name: str) -> Tuple[str, int]:
        """Detect category from vendor name"""
        vendor_lower = vendor_name.lower()
        best_match = None
        best_score = 0
        
        for category, data in CATEGORY_KEYWORDS.items():
            keywords = data['vendor_keywords']
            priority = data['priority']
            
            # Count keyword matches
            matches = sum(1 for kw in keywords if kw in vendor_lower)
            
            if matches > 0:
                score = matches * priority
                
                if score > best_score:
                    best_score = score
                    best_match = category
        
        if best_match:
            confidence = min(10, best_score)
            return (best_match, confidence)
        
        return (DEFAULT_CATEGORY, 0)
    
    @staticmethod
    def _from_items(items: List[str]) -> Tuple[str, int]:
        """Detect category from items list"""
        items_text = ' '.join(items).lower()
        
        category_scores = {}
        
        for category, data in CATEGORY_KEYWORDS.items():
            keywords = data['item_keywords']
            priority = data['priority']
            
            # Count keyword matches
            matches = sum(1 for kw in keywords if kw in items_text)
            
            if matches > 0:
                score = matches * priority
                category_scores[category] = score
        
        if category_scores:
            best_category = max(category_scores, key=category_scores.get)
            best_score = category_scores[best_category]
            
            # Confidence (items are less reliable than vendor)
            confidence = min(10, best_score // 2)
            return (best_category, confidence)
        
        return (DEFAULT_CATEGORY, 0)
    
    @staticmethod
    def _from_text(full_text: str) -> Tuple[str, int]:
        """Detect category from full text"""
        text_lower = full_text.lower()
        
        category_scores = {}
        
        for category, data in CATEGORY_KEYWORDS.items():
            all_keywords = data['vendor_keywords'] + data['item_keywords']
            priority = data['priority']
            
            # Count all keyword matches
            matches = sum(1 for kw in all_keywords if kw in text_lower)
            
            if matches > 0:
                score = matches * priority
                category_scores[category] = score
        
        if category_scores:
            best_category = max(category_scores, key=category_scores.get)
            best_score = category_scores[best_category]
            
            # Lower confidence for text
            confidence = min(10, best_score // 3)
            return (best_category, confidence)
        
        return (DEFAULT_CATEGORY, 0)

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def get_category_icon(category: str) -> str:
    """
    Get emoji icon for category
    
    Args:
        category: Category name
    
    Returns:
        Emoji string
    """
    icons = {
        'Health': '💊',
        'Grocery': '🛒',
        'Dining': '🍽️',
        'Transport': '🚗',
        'Utilities': '💡',
        'Shopping': '🛍️',
        'Entertainment': '🎬',
        'Education': '📚',
        'Personal Care': '💄',
        'Home & Garden': '🏡',
        'General': '📄'
    }
    return icons.get(category, '📄')

def get_category_color(category: str) -> str:
    """
    Get color code for category (hex)
    
    Args:
        category: Category name
    
    Returns:
        Hex color code
    """
    colors = {
        'Health': '#E74C3C',      # Red
        'Grocery': '#27AE60',     # Green
        'Dining': '#F39C12',      # Orange
        'Transport': '#3498DB',   # Blue
        'Utilities': '#9B59B6',   # Purple
        'Shopping': '#E91E63',    # Pink
        'Entertainment': '#FF5722', # Deep Orange
        'Education': '#2196F3',   # Light Blue
        'Personal Care': '#FF9800', # Amber
        'Home & Garden': '#8BC34A', # Light Green
        'General': '#95A5A6'      # Grey
    }
    return colors.get(category, '#95A5A6')

def get_all_categories() -> List[str]:
    """
    Get list of all available categories
    
    Returns:
        List of category names
    """
    return list(CATEGORY_KEYWORDS.keys()) + [DEFAULT_CATEGORY]

def get_category_info(category: str) -> dict:
    """
    Get complete information about a category
    
    Args:
        category: Category name
    
    Returns:
        Dict with icon, color, and keywords
    """
    return {
        'name': category,
        'icon': get_category_icon(category),
        'color': get_category_color(category),
        'keywords': CATEGORY_KEYWORDS.get(category, {})
    }