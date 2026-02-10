# FILE: app/services/wallet_service.py
# ============================================================================
# WALLET SERVICE - FIREBASE VERSION
# Transaction management using Firebase Firestore
# ============================================================================

from datetime import datetime, timedelta
from typing import List, Dict, Optional
from config import Config

# Import based on database type
if Config.DATABASE_TYPE == 'firebase':
    from app.models import firebase_database as db
else:
    from app.models.database import execute_query, execute_insert, get_db_connection

# ============================================================================
# WALLET SERVICE
# ============================================================================

class WalletService:
    """Core wallet operations"""
    
    @staticmethod
    def add_transaction(amount: float, trans_type: str, category: str, 
                       description: str = "") -> bool:
        """Add a new transaction"""
        try:
            if Config.DATABASE_TYPE == 'firebase':
                transaction_id = db.add_transaction(amount, trans_type, category, description)
                if transaction_id:
                    print(f"[WALLET] ✓ Added {trans_type}: Rs.{amount} ({category})")
                    return True
                return False
            else:
                # SQLite version
                date_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                query = '''
                    INSERT INTO transactions (date, type, amount, category, description)
                    VALUES (?, ?, ?, ?, ?)
                '''
                transaction_id = execute_insert(query, (date_str, trans_type, amount, category, description))
                if transaction_id:
                    print(f"[WALLET] ✓ Added {trans_type}: Rs.{amount} ({category})")
                    return True
                return False
                
        except Exception as e:
            print(f"[WALLET ERROR] Failed to add transaction: {e}")
            return False
    
    @staticmethod
    def get_balance() -> float:
        """Get current balance"""
        try:
            if Config.DATABASE_TYPE == 'firebase':
                return db.get_balance()
            else:
                # SQLite version
                query = '''
                    SELECT SUM(CASE WHEN type = 'income' THEN amount ELSE -amount END)
                    FROM transactions
                '''
                result = execute_query(query)
                return result[0][0] if result and result[0][0] else 0.0
                
        except Exception as e:
            print(f"[WALLET ERROR] Failed to get balance: {e}")
            return 0.0
    
    @staticmethod
    def get_total_income(days: Optional[int] = None) -> float:
        """Get total income, optionally filtered by days"""
        try:
            if Config.DATABASE_TYPE == 'firebase':
                if days:
                    start_date = datetime.now() - timedelta(days=days)
                    end_date = datetime.now()
                    return db.get_total_by_type('income', start_date, end_date)
                else:
                    return db.get_total_by_type('income')
            else:
                # SQLite version
                query = "SELECT SUM(amount) FROM transactions WHERE type='income'"
                params = []
                
                if days:
                    date_limit = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
                    query += " AND date >= ?"
                    params.append(date_limit)
                
                result = execute_query(query, tuple(params) if params else None)
                return result[0][0] if result and result[0][0] else 0.0
                
        except Exception as e:
            print(f"[WALLET ERROR] Failed to get income: {e}")
            return 0.0
    
    @staticmethod
    def get_total_expense(days: Optional[int] = None) -> float:
        """Get total expenses, optionally filtered by days"""
        try:
            if Config.DATABASE_TYPE == 'firebase':
                if days:
                    start_date = datetime.now() - timedelta(days=days)
                    end_date = datetime.now()
                    return db.get_total_by_type('expense', start_date, end_date)
                else:
                    return db.get_total_by_type('expense')
            else:
                # SQLite version
                query = "SELECT SUM(amount) FROM transactions WHERE type='expense'"
                params = []
                
                if days:
                    date_limit = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
                    query += " AND date >= ?"
                    params.append(date_limit)
                
                result = execute_query(query, tuple(params) if params else None)
                return result[0][0] if result and result[0][0] else 0.0
                
        except Exception as e:
            print(f"[WALLET ERROR] Failed to get expense: {e}")
            return 0.0
    
    @staticmethod
    def get_recent_transactions(limit: int = 5) -> List[Dict]:
        """Get recent transactions"""
        try:
            if Config.DATABASE_TYPE == 'firebase':
                return db.get_recent_transactions(limit)
            else:
                # SQLite version
                query = '''
                    SELECT date, type, amount, category, description
                    FROM transactions
                    ORDER BY created_at DESC
                    LIMIT ?
                '''
                result = execute_query(query, (limit,))
                
                if result:
                    transactions = []
                    for row in result:
                        transactions.append({
                            'date': row[0],
                            'type': row[1],
                            'amount': row[2],
                            'category': row[3],
                            'description': row[4]
                        })
                    return transactions
                return []
                
        except Exception as e:
            print(f"[WALLET ERROR] Failed to get transactions: {e}")
            return []
    
    @staticmethod
    def get_category_breakdown(days: int = 7) -> Dict[str, float]:
        """Get spending breakdown by category"""
        try:
            if Config.DATABASE_TYPE == 'firebase':
                start_date = datetime.now() - timedelta(days=days)
                end_date = datetime.now()
                return db.get_category_breakdown(start_date, end_date)
            else:
                # SQLite version
                date_limit = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
                query = '''
                    SELECT category, SUM(amount) as total
                    FROM transactions
                    WHERE type = 'expense' AND date >= ?
                    GROUP BY category
                    ORDER BY total DESC
                '''
                result = execute_query(query, (date_limit,))
                
                if result:
                    breakdown = {}
                    for row in result:
                        breakdown[row[0]] = row[1]
                    return breakdown
                return {}
                
        except Exception as e:
            print(f"[WALLET ERROR] Failed to get breakdown: {e}")
            return {}
    
    @staticmethod
    def get_transaction_count() -> int:
        """Get total number of transactions"""
        try:
            if Config.DATABASE_TYPE == 'firebase':
                return db.get_collection_count(Config.TRANSACTIONS_COLLECTION)
            else:
                # SQLite version
                query = "SELECT COUNT(*) FROM transactions"
                result = execute_query(query)
                return result[0][0] if result else 0
                
        except Exception as e:
            print(f"[WALLET ERROR] Failed to get count: {e}")
            return 0

# ============================================================================
# QUESTION ANSWERER
# ============================================================================

class QuestionAnswerer:
    """Answer natural language questions about wallet"""
    
    @staticmethod
    def process_question(question: str) -> str:
        """Process natural language question and return answer"""
        q_lower = question.lower()
        
        # Balance queries
        if any(word in q_lower for word in ["balance", "how much money", "total money"]):
            balance = WalletService.get_balance()
            return f"Your current balance is Rs. {balance:,.2f}"
        
        # Total income
        if any(word in q_lower for word in ["total income", "all income"]):
            income = WalletService.get_total_income()
            return f"Your total income is Rs. {income:,.2f}"
        
        # Total expenses
        if any(word in q_lower for word in ["total expense", "total spend", "all expense"]):
            expense = WalletService.get_total_expense()
            return f"Your total expenses are Rs. {expense:,.2f}"
        
        # Time-based spending
        if "spend" in q_lower or "expense" in q_lower:
            days = 7
            period = "this week"
            
            if "today" in q_lower:
                days = 1
                period = "today"
            elif "month" in q_lower:
                days = 30
                period = "this month"
            elif "week" in q_lower:
                days = 7
                period = "this week"
            
            expense = WalletService.get_total_expense(days=days)
            return f"You spent Rs. {expense:,.2f} {period}"
        
        # Time-based income
        if "income" in q_lower or "earn" in q_lower or "receive" in q_lower:
            days = 7
            period = "this week"
            
            if "today" in q_lower:
                days = 1
                period = "today"
            elif "month" in q_lower:
                days = 30
                period = "this month"
            
            income = WalletService.get_total_income(days=days)
            return f"You received Rs. {income:,.2f} {period}"
        
        # Recent transactions
        if "recent" in q_lower or "last transaction" in q_lower:
            transactions = WalletService.get_recent_transactions(3)
            if transactions:
                msg = f"Your last {len(transactions)} transactions: "
                details = [
                    f"{t['type']} of Rs.{t['amount']:.2f} on {t['date'][:10]}"
                    for t in transactions
                ]
                return msg + ". ".join(details)
            return "No transactions found"
        
        # Category breakdown
        if "category" in q_lower or "breakdown" in q_lower:
            breakdown = WalletService.get_category_breakdown()
            if breakdown:
                msg = "Spending by category: "
                details = [f"{cat}: Rs.{amt:.2f}" for cat, amt in breakdown.items()]
                return msg + ", ".join(details)
            return "No expense data available"
        
        # Transaction count
        if "how many transaction" in q_lower or "number of transaction" in q_lower:
            count = WalletService.get_transaction_count()
            return f"You have {count} transactions recorded"
        
        return "Sorry, I didn't understand. Try asking about balance, income, expenses, or recent transactions."

# ============================================================================
# SUMMARY GENERATOR
# ============================================================================

class SummaryGenerator:
    """Generate spending summaries"""
    
    @staticmethod
    def generate_weekly() -> Dict:
        """Generate weekly summary"""
        try:
            today = datetime.now()
            week_start = today - timedelta(days=today.weekday())
            week_end = week_start + timedelta(days=6)
            
            week_start_str = week_start.strftime("%Y-%m-%d")
            week_end_str = week_end.strftime("%Y-%m-%d")
            
            if Config.DATABASE_TYPE == 'firebase':
                # Get spending and income
                total_spending = db.get_total_by_type('expense', week_start, week_end)
                total_income = db.get_total_by_type('income', week_start, week_end)
                
                # Get category breakdown
                breakdown = db.get_category_breakdown(week_start, week_end)
                
            else:
                # SQLite version
                from app.models.database import execute_query
                
                query = '''
                    SELECT COALESCE(SUM(amount), 0)
                    FROM transactions
                    WHERE type = 'expense' AND date >= ? AND date <= ?
                '''
                result = execute_query(query, (week_start_str, week_end_str + " 23:59:59"))
                total_spending = result[0][0] if result else 0.0
                
                query = '''
                    SELECT COALESCE(SUM(amount), 0)
                    FROM transactions
                    WHERE type = 'income' AND date >= ? AND date <= ?
                '''
                result = execute_query(query, (week_start_str, week_end_str + " 23:59:59"))
                total_income = result[0][0] if result else 0.0
                
                query = '''
                    SELECT category, SUM(amount) as total
                    FROM transactions
                    WHERE type = 'expense' AND date >= ? AND date <= ?
                    GROUP BY category
                    ORDER BY total DESC
                '''
                result = execute_query(query, (week_start_str, week_end_str + " 23:59:59"))
                
                breakdown = {}
                if result:
                    for row in result:
                        breakdown[row[0]] = row[1]
            
            return {
                'week_start': week_start_str,
                'week_end': week_end_str,
                'total_spending': total_spending,
                'total_income': total_income,
                'breakdown': breakdown,
                'message': f"Total spending this week: Rs. {total_spending:,.2f}"
            }
            
        except Exception as e:
            print(f"[SUMMARY ERROR] {e}")
            return {
                'message': 'Could not generate summary',
                'total_spending': 0.0,
                'total_income': 0.0
            }