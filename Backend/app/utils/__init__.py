# FILE: app/utils/__init__.py
# ============================================================================

"""Utility functions and helpers"""

import re
from datetime import datetime

def clean_text(text):
    """Clean and normalize text"""
    if not text:
        return ""
    
    text = ' '.join(text.split())
    text = re.sub(r'\b[^\w\s]\b', '', text)
    return text.strip()

def parse_date(date_str):
    """Parse date string to datetime"""
    date_formats = [
        "%Y-%m-%d",
        "%d/%m/%Y",
        "%d-%m-%Y",
        "%Y/%m/%d",
        "%d %b %Y",
        "%d %B %Y"
    ]
    
    for fmt in date_formats:
        try:
            return datetime.strptime(date_str, fmt)
        except:
            continue
    
    return None

def format_currency(amount):
    """Format amount as currency"""
    from app.config.settings import CURRENCY_SYMBOL
    return f"{CURRENCY_SYMBOL} {amount:,.2f}"

def extract_numbers(text):
    """Extract all numbers from text"""
    return re.findall(r'\d+\.?\d*', text)

def is_valid_amount(amount):
    """Check if amount is valid"""
    from app.config.settings import MIN_BILL_AMOUNT, MAX_BILL_AMOUNT
    try:
        amt = float(amount)
        return MIN_BILL_AMOUNT <= amt <= MAX_BILL_AMOUNT
    except:
        return False