# FILE: app/models/firebase_database.py
# ============================================================================
# FIREBASE DATABASE OPERATIONS
# Complete replacement for SQLite database
# ============================================================================

"""
Firebase Database Operations
Handles all Firestore interactions for Smart Wallet
"""

import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime
from typing import Dict, List, Optional
from config import Config
import os

# ============================================================================
# FIREBASE INITIALIZATION
# ============================================================================

# Global Firestore client
db = None

def init_firebase():
    """Initialize Firebase Admin SDK"""
    global db
    
    try:
        if not firebase_admin._apps:
            # Check if credentials file exists
            if not os.path.exists(Config.FIREBASE_CREDENTIALS):
                print(f"[FIREBASE] ✗ Credentials file not found: {Config.FIREBASE_CREDENTIALS}")
                print("[FIREBASE] Please download firebase-credentials.json from Firebase Console")
                return False
            
            # Initialize Firebase
            cred = credentials.Certificate(Config.FIREBASE_CREDENTIALS)
            firebase_admin.initialize_app(cred)
            
            print("[FIREBASE] ✓ Firebase Admin SDK initialized")
        
        # Get Firestore client
        db = firestore.client()
        print("[FIREBASE] ✓ Firestore client ready")
        
        # Create indexes (if needed)
        _create_indexes()
        
        return True
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Initialization failed: {e}")
        return False

def _create_indexes():
    """Create necessary indexes (done in Firebase Console)"""
    print("[FIREBASE] Note: Create these indexes in Firebase Console if needed:")
    print("  1. transactions: date (desc)")
    print("  2. bills: scan_date (desc)")
    print("  3. transactions: category, date (desc)")

# ============================================================================
# TRANSACTION OPERATIONS
# ============================================================================

def add_transaction(amount: float, trans_type: str, category: str, 
                   description: str = "", bill_id: str = None) -> Optional[str]:
    """
    Add a new transaction to Firestore
    
    Returns:
        Transaction ID or None on error
    """
    try:
        transaction_data = {
            'date': datetime.now(),
            'type': trans_type,
            'amount': amount,
            'category': category,
            'description': description,
            'bill_id': bill_id,
            'created_at': firestore.SERVER_TIMESTAMP
        }
        
        doc_ref = db.collection(Config.TRANSACTIONS_COLLECTION).document()
        doc_ref.set(transaction_data)
        
        print(f"[FIREBASE] ✓ Transaction added: {doc_ref.id}")
        return doc_ref.id
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Add transaction failed: {e}")
        return None

def get_balance() -> float:
    """Calculate current balance"""
    try:
        transactions = db.collection(Config.TRANSACTIONS_COLLECTION).stream()
        
        balance = 0.0
        for transaction in transactions:
            data = transaction.to_dict()
            if data['type'] == 'income':
                balance += data['amount']
            else:
                balance -= data['amount']
        
        return balance
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Get balance failed: {e}")
        return 0.0

def get_recent_transactions(limit: int = 5) -> List[Dict]:
    """Get recent transactions"""
    try:
        transactions_ref = db.collection(Config.TRANSACTIONS_COLLECTION) \
            .order_by('date', direction=firestore.Query.DESCENDING) \
            .limit(limit)
        
        transactions = []
        for doc in transactions_ref.stream():
            data = doc.to_dict()
            data['id'] = doc.id
            
            # Convert Firestore timestamp to string
            if isinstance(data.get('date'), datetime):
                data['date'] = data['date'].strftime("%Y-%m-%d %H:%M:%S")
            
            transactions.append(data)
        
        return transactions
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Get transactions failed: {e}")
        return []

def get_transactions_by_date_range(start_date: datetime, end_date: datetime) -> List[Dict]:
    """Get transactions within date range"""
    try:
        transactions_ref = db.collection(Config.TRANSACTIONS_COLLECTION) \
            .where('date', '>=', start_date) \
            .where('date', '<=', end_date) \
            .order_by('date', direction=firestore.Query.DESCENDING)
        
        transactions = []
        for doc in transactions_ref.stream():
            data = doc.to_dict()
            data['id'] = doc.id
            
            if isinstance(data.get('date'), datetime):
                data['date'] = data['date'].strftime("%Y-%m-%d %H:%M:%S")
            
            transactions.append(data)
        
        return transactions
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Get transactions by date failed: {e}")
        return []

def get_total_by_type(trans_type: str, start_date: datetime = None, 
                     end_date: datetime = None) -> float:
    """Get total amount for transaction type"""
    try:
        query = db.collection(Config.TRANSACTIONS_COLLECTION) \
            .where('type', '==', trans_type)
        
        if start_date:
            query = query.where('date', '>=', start_date)
        if end_date:
            query = query.where('date', '<=', end_date)
        
        total = 0.0
        for doc in query.stream():
            data = doc.to_dict()
            total += data['amount']
        
        return total
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Get total failed: {e}")
        return 0.0

def get_category_breakdown(start_date: datetime, end_date: datetime) -> Dict[str, float]:
    """Get spending breakdown by category"""
    try:
        transactions_ref = db.collection(Config.TRANSACTIONS_COLLECTION) \
            .where('type', '==', 'expense') \
            .where('date', '>=', start_date) \
            .where('date', '<=', end_date)
        
        breakdown = {}
        for doc in transactions_ref.stream():
            data = doc.to_dict()
            category = data['category']
            amount = data['amount']
            
            if category in breakdown:
                breakdown[category] += amount
            else:
                breakdown[category] = amount
        
        return breakdown
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Get breakdown failed: {e}")
        return {}

# ============================================================================
# BILL OPERATIONS
# ============================================================================

def save_bill(bill_data: Dict) -> Optional[str]:
    """Save bill to Firestore"""
    try:
        # Check for duplicate
        existing = db.collection(Config.BILLS_COLLECTION) \
            .where('vendor', '==', bill_data['vendor']) \
            .where('total_amount', '==', bill_data['total_amount']) \
            .where('bill_date', '==', bill_data.get('date', '')) \
            .limit(1) \
            .stream()
        
        for doc in existing:
            print(f"[FIREBASE] ⚠️  Duplicate bill detected: {doc.id}")
            return doc.id
        
        # Create new bill
        bill_document = {
            'vendor': bill_data['vendor'],
            'total_amount': bill_data['total_amount'],
            'category': bill_data['category'],
            'bill_date': bill_data.get('date', ''),
            'address': bill_data.get('address', ''),
            'cash_amount': bill_data.get('cash', 0.0),
            'change_amount': bill_data.get('change', 0.0),
            'confirmed': False,
            'scan_date': firestore.SERVER_TIMESTAMP
        }
        
        doc_ref = db.collection(Config.BILLS_COLLECTION).document()
        doc_ref.set(bill_document)
        
        print(f"[FIREBASE] ✓ Bill saved: {doc_ref.id}")
        return doc_ref.id
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Save bill failed: {e}")
        return None

def get_bill(bill_id: str) -> Optional[Dict]:
    """Get bill by ID"""
    try:
        doc = db.collection(Config.BILLS_COLLECTION).document(bill_id).get()
        
        if doc.exists:
            data = doc.to_dict()
            data['id'] = doc.id
            return data
        
        return None
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Get bill failed: {e}")
        return None

def confirm_bill(bill_id: str) -> tuple[bool, str]:
    """Confirm bill and create transaction"""
    try:
        # Get bill
        bill = get_bill(bill_id)
        
        if not bill:
            return False, "Bill not found"
        
        if bill.get('confirmed'):
            return False, "Bill already confirmed"
        
        # Create transaction
        transaction_id = add_transaction(
            amount=bill['total_amount'],
            trans_type='expense',
            category=bill['category'],
            description=f"Bill from {bill['vendor']}",
            bill_id=bill_id
        )
        
        if not transaction_id:
            return False, "Failed to create transaction"
        
        # Mark bill as confirmed
        db.collection(Config.BILLS_COLLECTION).document(bill_id).update({
            'confirmed': True,
            'transaction_id': transaction_id
        })
        
        print(f"[FIREBASE] ✓ Bill confirmed: {bill_id}")
        return True, f"Saved under {bill['category']} category"
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Confirm bill failed: {e}")
        return False, str(e)

def get_recent_bills(limit: int = 10) -> List[Dict]:
    """Get recent bills"""
    try:
        bills_ref = db.collection(Config.BILLS_COLLECTION) \
            .order_by('scan_date', direction=firestore.Query.DESCENDING) \
            .limit(limit)
        
        bills = []
        for doc in bills_ref.stream():
            data = doc.to_dict()
            data['id'] = doc.id
            
            # Convert timestamps
            if 'scan_date' in data and data['scan_date']:
                data['scan_date'] = data['scan_date'].strftime("%Y-%m-%d %H:%M:%S")
            
            bills.append(data)
        
        return bills
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Get recent bills failed: {e}")
        return []

def get_all_bills() -> List[Dict]:
    """Get all bills"""
    try:
        bills_ref = db.collection(Config.BILLS_COLLECTION) \
            .order_by('scan_date', direction=firestore.Query.DESCENDING)
        
        bills = []
        for doc in bills_ref.stream():
            data = doc.to_dict()
            data['id'] = doc.id
            
            if 'scan_date' in data and data['scan_date']:
                data['scan_date'] = data['scan_date'].strftime("%Y-%m-%d %H:%M:%S")
            
            bills.append(data)
        
        return bills
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Get all bills failed: {e}")
        return []

def delete_bill(bill_id: str) -> bool:
    """Delete a bill"""
    try:
        db.collection(Config.BILLS_COLLECTION).document(bill_id).delete()
        print(f"[FIREBASE] ✓ Bill deleted: {bill_id}")
        return True
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Delete bill failed: {e}")
        return False

# ============================================================================
# WEEKLY SUMMARY OPERATIONS
# ============================================================================

def save_weekly_summary(summary_data: Dict) -> Optional[str]:
    """Save weekly summary"""
    try:
        doc_ref = db.collection(Config.WEEKLY_SUMMARIES_COLLECTION).document()
        
        summary_document = {
            'week_start': summary_data['week_start'],
            'week_end': summary_data['week_end'],
            'total_spending': summary_data['total_spending'],
            'total_income': summary_data.get('total_income', 0.0),
            'category_breakdown': summary_data.get('breakdown', {}),
            'created_at': firestore.SERVER_TIMESTAMP
        }
        
        doc_ref.set(summary_document)
        print(f"[FIREBASE] ✓ Weekly summary saved: {doc_ref.id}")
        return doc_ref.id
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Save summary failed: {e}")
        return None

def get_weekly_summary(week_start: str) -> Optional[Dict]:
    """Get weekly summary by start date"""
    try:
        summaries = db.collection(Config.WEEKLY_SUMMARIES_COLLECTION) \
            .where('week_start', '==', week_start) \
            .limit(1) \
            .stream()
        
        for doc in summaries:
            data = doc.to_dict()
            data['id'] = doc.id
            return data
        
        return None
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Get summary failed: {e}")
        return None

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def get_collection_count(collection_name: str) -> int:
    """Get document count in collection"""
    try:
        docs = db.collection(collection_name).stream()
        return sum(1 for _ in docs)
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Get count failed: {e}")
        return 0

def get_database_info() -> Dict:
    """Get database statistics"""
    try:
        info = {
            'database_type': 'Firebase Firestore',
            'collections': {
                'transactions': {
                    'count': get_collection_count(Config.TRANSACTIONS_COLLECTION)
                },
                'bills': {
                    'count': get_collection_count(Config.BILLS_COLLECTION)
                },
                'weekly_summaries': {
                    'count': get_collection_count(Config.WEEKLY_SUMMARIES_COLLECTION)
                }
            }
        }
        
        return info
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Get database info failed: {e}")
        return {}

def clear_collection(collection_name: str) -> bool:
    """Clear all documents in a collection"""
    try:
        docs = db.collection(collection_name).stream()
        
        for doc in docs:
            doc.reference.delete()
        
        print(f"[FIREBASE] ✓ Collection cleared: {collection_name}")
        return True
        
    except Exception as e:
        print(f"[FIREBASE] ✗ Clear collection failed: {e}")
        return False

# ============================================================================
# INITIALIZATION CHECK
# ============================================================================

def ensure_firebase_ready() -> bool:
    """Ensure Firebase is initialized and ready"""
    global db
    
    if db is None:
        return init_firebase()
    
    return True