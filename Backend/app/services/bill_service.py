# FILE: app/services/bill_service.py
# ============================================================================
# BILL SERVICE - FIREBASE VERSION
# Bill processing with Firebase Firestore
# ============================================================================

import json
from datetime import datetime
from typing import Dict, Optional, Tuple, List
from config import Config
from app.services.category_service import CategoryDetector, get_category_icon
from app.services.field_extractor import extract_receipt_fields

# Import based on database type
if Config.DATABASE_TYPE == 'firebase':
    from app.models import firebase_database as db
else:
    from app.models.database import execute_insert, execute_query, execute_update, get_db_connection

# ============================================================================
# BILL EXTRACTOR (Same for both databases)
# ============================================================================

class BillExtractor:
    """Extract and process bill information"""
    
    @staticmethod
    def process_bill(image_bytes: bytes) -> Optional[Dict]:
        """Process bill image and extract all fields"""
        print("[BILL] Processing bill image...")
        
        # Extract fields using YOLO + OCR
        result = extract_receipt_fields(image_bytes)
        
        if not result['success']:
            print(f"[BILL] ✗ Extraction failed: {result.get('error', 'Unknown error')}")
            return None
        
        # Get extracted data
        vendor = result.get('company', '').strip() or 'Unknown'
        address = result.get('address', '').strip()
        date = result.get('date', '').strip()
        total = result.get('total', '').strip()
        cash = result.get('cash', '').strip()
        change = result.get('change', '').strip()
        menu_items = result.get('menu_items', [])  # ⭐ GET MENU ITEMS
        
        # Convert amounts
        try:
            total_amount = float(total) if total else 0.0
            cash_amount = float(cash) if cash else 0.0
            change_amount = float(change) if change else 0.0
        except:
            total_amount = cash_amount = change_amount = 0.0
        
        # Auto-calculate if needed
        if total_amount == 0 and cash_amount > 0:
            total_amount = cash_amount
            print("[BILL] Using cash as total")
        
        if cash_amount > 0 and total_amount > 0 and change_amount == 0:
            change_amount = cash_amount - total_amount
            print(f"[BILL] Calculated change: Rs.{change_amount}")
        
        # Detect category
        category = CategoryDetector.detect(vendor, [], "")
        
        # ⭐ BUILD BILL INFO WITH MENU ITEMS
        bill_info = {
            'vendor': vendor,
            'address': address,
            'date': date,
            'total_amount': total_amount,
            'cash': cash_amount,
            'change': change_amount,
            'category': category,
            'menu_items': menu_items,  # ⭐ INCLUDE MENU ITEMS
            'scanned_at': datetime.now().isoformat()
        }
        
        # ⭐ DEBUG: Print what we're sending
        print(f"[BILL INFO DEBUG] menu_items type: {type(menu_items)}")
        print(f"[BILL INFO DEBUG] menu_items count: {len(menu_items)}")
        print(f"[BILL INFO DEBUG] menu_items value: {menu_items}")
        
        print(f"[BILL] ✓ Processed: {vendor} - Rs.{total_amount} ({category}) - {len(menu_items)} items")
        
        return bill_info
    
    @staticmethod
    def generate_confirmation(bill_info: Dict) -> str:
        """Generate confirmation message for user"""
        vendor = bill_info['vendor']
        amount = bill_info['total_amount']
        category = bill_info['category']
        icon = get_category_icon(category)
        
        msg = f"{icon} {vendor}\n"
        msg += f"💰 Total: Rs. {amount:.2f}\n"
        msg += f"📂 Category: {category}\n"
        
        if bill_info.get('date'):
            msg += f"📅 Date: {bill_info['date']}\n"
        
        if bill_info.get('address'):
            msg += f"📍 Address: {bill_info['address']}\n"
        
        if bill_info.get('cash'):
            msg += f"💵 Cash: Rs. {bill_info['cash']:.2f}\n"
        
        if bill_info.get('change'):
            msg += f"💸 Change: Rs. {bill_info['change']:.2f}\n"
        
        return msg

# ============================================================================
# BILL REPOSITORY (Database operations)
# ============================================================================

class BillRepository:
    """Handle bill database operations"""
    
    @staticmethod
    def save_bill(bill_info: Dict) -> Optional[str]:
        """Save bill to database"""
        try:
            if Config.DATABASE_TYPE == 'firebase':
                # Firebase version
                bill_id = db.save_bill(bill_info)
                
                if bill_id:
                    print(f"[BILL REPO] ✓ Bill saved: {bill_id}")
                    return bill_id
                else:
                    print("[BILL REPO] ⚠️  Bill might be duplicate")
                    return None
                    
            else:
                # SQLite version
                vendor = bill_info['vendor']
                total_amount = bill_info['total_amount']
                bill_date = bill_info.get('date', '')
                
                # Check for existing bill
                check_query = '''
                    SELECT id FROM bills 
                    WHERE vendor = ? AND total_amount = ? AND bill_date = ?
                '''
                existing = execute_query(check_query, (vendor, total_amount, bill_date))
                
                if existing and len(existing) > 0:
                    print(f"[BILL REPO] ⚠️  Duplicate bill detected: ID {existing[0][0]}")
                    return str(existing[0][0])
                
                # Insert new bill
                query = '''
                    INSERT INTO bills 
                    (vendor, total_amount, category, bill_date, address, 
                     raw_text, items_json, cash_amount, change_amount, confirmed)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                '''
                
                bill_id = execute_insert(query, (
                    vendor,
                    total_amount,
                    bill_info['category'],
                    bill_date,
                    bill_info.get('address', ''),
                    bill_info.get('scanned_at', ''),
                    json.dumps([]),
                    bill_info.get('cash', 0.0),
                    bill_info.get('change', 0.0)
                ))
                
                if bill_id and bill_id > 0:
                    print(f"[BILL REPO] ✓ New bill saved: ID {bill_id}")
                    return str(bill_id)
                
                return None
                
        except Exception as e:
            print(f"[BILL REPO ERROR] Save failed: {e}")
            import traceback
            traceback.print_exc()
            return None
    
    @staticmethod
    def get_all_bills() -> List[Dict]:
        """Get ALL bills from database"""
        try:
            if Config.DATABASE_TYPE == 'firebase':
                return db.get_all_bills()
            else:
                query = '''
                    SELECT id, vendor, total_amount, category, bill_date, 
                           address, confirmed, scan_date
                    FROM bills
                    ORDER BY scan_date DESC
                '''
                result = execute_query(query)
                
                if result:
                    bills = []
                    for row in result:
                        bills.append({
                            'id': str(row[0]),
                            'vendor': row[1],
                            'total_amount': row[2],
                            'category': row[3],
                            'bill_date': row[4],
                            'address': row[5],
                            'confirmed': row[6] == 1,
                            'scan_date': row[7]
                        })
                    return bills
                return []
                
        except Exception as e:
            print(f"[BILL REPO ERROR] Get all bills failed: {e}")
            return []
    
    @staticmethod
    def confirm_bill(bill_id: str) -> Tuple[bool, str]:
        """Confirm bill and create expense transaction"""
        try:
            if Config.DATABASE_TYPE == 'firebase':
                return db.confirm_bill(bill_id)
            else:
                # SQLite version
                conn = get_db_connection()
                cursor = conn.cursor()
                
                cursor.execute('SELECT * FROM bills WHERE id = ?', (bill_id,))
                bill = cursor.fetchone()
                
                if not bill:
                    conn.close()
                    return False, "Bill not found"
                
                bill_dict = dict(bill)
                
                if bill_dict.get('confirmed', 0) == 1:
                    conn.close()
                    return False, "Bill already confirmed"
                
                # Create transaction
                cursor.execute('''
                    INSERT INTO transactions (date, type, amount, category, description, bill_id)
                    VALUES (?, 'expense', ?, ?, ?, ?)
                ''', (
                    bill_dict.get('bill_date') or datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    bill_dict['total_amount'],
                    bill_dict['category'],
                    f"Bill from {bill_dict['vendor']}",
                    bill_id
                ))
                
                # Mark bill as confirmed
                cursor.execute('UPDATE bills SET confirmed = 1 WHERE id = ?', (bill_id,))
                
                conn.commit()
                conn.close()
                
                print(f"[BILL REPO] ✓ Bill {bill_id} confirmed")
                return True, f"Saved under {bill_dict['category']} category"
                
        except Exception as e:
            print(f"[BILL REPO ERROR] Confirm failed: {e}")
            import traceback
            traceback.print_exc()
            return False, str(e)
    
    @staticmethod
    def get_recent_bills(limit: int = 10) -> List[Dict]:
        """Get recent bills"""
        try:
            if Config.DATABASE_TYPE == 'firebase':
                return db.get_recent_bills(limit)
            else:
                query = '''
                    SELECT id, vendor, total_amount, category, bill_date, confirmed
                    FROM bills
                    ORDER BY scan_date DESC
                    LIMIT ?
                '''
                result = execute_query(query, (limit,))
                
                if result:
                    bills = []
                    for row in result:
                        bills.append({
                            'id': str(row[0]),
                            'vendor': row[1],
                            'total_amount': row[2],
                            'category': row[3],
                            'date': row[4],
                            'confirmed': row[5] == 1
                        })
                    return bills
                return []
                
        except Exception as e:
            print(f"[BILL REPO ERROR] Get recent failed: {e}")
            return []
    
    @staticmethod
    def delete_bill(bill_id: str) -> bool:
        """Delete a bill from database"""
        try:
            if Config.DATABASE_TYPE == 'firebase':
                return db.delete_bill(bill_id)
            else:
                conn = get_db_connection()
                cursor = conn.cursor()
                cursor.execute('DELETE FROM bills WHERE id = ?', (bill_id,))
                conn.commit()
                conn.close()
                
                print(f"[BILL REPO] ✓ Bill {bill_id} deleted")
                return True
                
        except Exception as e:
            print(f"[BILL REPO ERROR] Delete failed: {e}")
            return False