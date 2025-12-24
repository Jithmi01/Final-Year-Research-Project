# ============================================================================
# FILE: app/models/database.py
# Complete database setup and operations
# ============================================================================

"""
Database Models and Operations
Handles all database interactions for Smart Wallet
"""

import sqlite3
from datetime import datetime
from typing import Dict, List, Optional, Tuple, Any
from app.config.settings import DB_NAME

# ============================================================================
# DATABASE INITIALIZATION
# ============================================================================

def init_all_databases():
    """Initialize all database tables"""
    print("[DB] Initializing database tables...")
    
    init_transactions_table()
    init_bills_table()
    init_weekly_summaries_table()
    init_savings_goals_table()
    
    print("[DB] ✓ All tables initialized successfully")

def init_transactions_table():
    """Initialize transactions table"""
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            type TEXT NOT NULL CHECK(type IN ('income', 'expense')),
            amount REAL NOT NULL CHECK(amount > 0),
            category TEXT NOT NULL,
            description TEXT,
            bill_id INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (bill_id) REFERENCES bills(id)
        )
    ''')
    
    # Create indexes for better performance
    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_transactions_date 
        ON transactions(date)
    ''')
    
    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_transactions_type 
        ON transactions(type)
    ''')
    
    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_transactions_category 
        ON transactions(category)
    ''')
    
    conn.commit()
    conn.close()
    print("[DB] ✓ Transactions table ready")

def init_bills_table():
    """Initialize bills table"""
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS bills (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            vendor TEXT,
            total_amount REAL NOT NULL,
            category TEXT NOT NULL,
            bill_date TEXT,
            address TEXT,
            scan_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            raw_text TEXT,
            items_json TEXT,
            cash_amount REAL DEFAULT 0,
            change_amount REAL DEFAULT 0,
            confirmed INTEGER DEFAULT 0 CHECK(confirmed IN (0, 1)),
            UNIQUE(vendor, total_amount, bill_date)
        )
    ''')
    
    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_bills_vendor 
        ON bills(vendor)
    ''')
    
    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_bills_confirmed 
        ON bills(confirmed)
    ''')
    
    conn.commit()
    conn.close()
    print("[DB] ✓ Bills table ready")

def init_weekly_summaries_table():
    """Initialize weekly summaries table"""
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS weekly_summaries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            week_start TEXT NOT NULL,
            week_end TEXT NOT NULL,
            total_spending REAL DEFAULT 0,
            total_income REAL DEFAULT 0,
            category_breakdown TEXT,
            comparison_text TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(week_start)
        )
    ''')
    
    conn.commit()
    conn.close()
    print("[DB] ✓ Weekly summaries table ready")

def init_savings_goals_table():
    """Initialize savings goals table"""
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS savings_goals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            goal_amount REAL NOT NULL CHECK(goal_amount > 0),
            current_savings REAL DEFAULT 0 CHECK(current_savings >= 0),
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            description TEXT,
            is_active INTEGER DEFAULT 1 CHECK(is_active IN (0, 1)),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            completed_at TIMESTAMP
        )
    ''')
    
    conn.commit()
    conn.close()
    print("[DB] ✓ Savings goals table ready")

# ============================================================================
# CONNECTION HELPERS
# ============================================================================

def get_db_connection():
    """Get database connection with row factory"""
    conn = sqlite3.connect(DB_NAME)
    conn.row_factory = sqlite3.Row  # Enable column access by name
    return conn

def dict_from_row(row):
    """Convert sqlite3.Row to dict"""
    return dict(zip(row.keys(), row))

# ============================================================================
# GENERIC QUERY FUNCTIONS
# ============================================================================

def execute_query(query: str, params: Optional[Tuple] = None) -> Optional[List]:
    """
    Execute a SELECT query and return results
    
    Args:
        query: SQL query string
        params: Query parameters tuple
    
    Returns:
        List of results or None on error
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        if params:
            cursor.execute(query, params)
        else:
            cursor.execute(query)
        
        results = cursor.fetchall()
        conn.close()
        
        return results
        
    except Exception as e:
        print(f"[DB ERROR] Query failed: {e}")
        print(f"[DB ERROR] Query: {query}")
        return None

def execute_insert(query: str, params: Tuple) -> Optional[int]:
    """
    Execute an INSERT query and return last row id
    
    Args:
        query: SQL INSERT query
        params: Query parameters tuple
    
    Returns:
        Last inserted row id or None on error
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute(query, params)
        last_id = cursor.lastrowid
        
        conn.commit()
        conn.close()
        
        return last_id
        
    except Exception as e:
        print(f"[DB ERROR] Insert failed: {e}")
        print(f"[DB ERROR] Query: {query}")
        return None

def execute_update(query: str, params: Tuple) -> bool:
    """
    Execute an UPDATE query
    
    Args:
        query: SQL UPDATE query
        params: Query parameters tuple
    
    Returns:
        True if successful, False otherwise
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute(query, params)
        
        conn.commit()
        conn.close()
        
        return True
        
    except Exception as e:
        print(f"[DB ERROR] Update failed: {e}")
        return False

def execute_delete(query: str, params: Tuple) -> bool:
    """
    Execute a DELETE query
    
    Args:
        query: SQL DELETE query
        params: Query parameters tuple
    
    Returns:
        True if successful, False otherwise
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute(query, params)
        
        conn.commit()
        conn.close()
        
        return True
        
    except Exception as e:
        print(f"[DB ERROR] Delete failed: {e}")
        return False

# ============================================================================
# TRANSACTION HELPERS
# ============================================================================

def execute_transaction(operations: List[Tuple[str, Tuple]]) -> bool:
    """
    Execute multiple operations in a transaction
    
    Args:
        operations: List of (query, params) tuples
    
    Returns:
        True if all operations succeeded, False otherwise
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Execute all operations
        for query, params in operations:
            cursor.execute(query, params)
        
        # Commit if all succeeded
        conn.commit()
        conn.close()
        
        return True
        
    except Exception as e:
        print(f"[DB ERROR] Transaction failed: {e}")
        if conn:
            conn.rollback()
            conn.close()
        return False

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def table_exists(table_name: str) -> bool:
    """Check if table exists"""
    try:
        query = '''
            SELECT name FROM sqlite_master 
            WHERE type='table' AND name=?
        '''
        result = execute_query(query, (table_name,))
        return result is not None and len(result) > 0
        
    except Exception as e:
        print(f"[DB ERROR] Table check failed: {e}")
        return False

def get_table_row_count(table_name: str) -> int:
    """Get number of rows in table"""
    try:
        query = f"SELECT COUNT(*) FROM {table_name}"
        result = execute_query(query)
        return result[0][0] if result else 0
        
    except Exception as e:
        print(f"[DB ERROR] Row count failed: {e}")
        return 0

def clear_table(table_name: str) -> bool:
    """Clear all data from table"""
    try:
        query = f"DELETE FROM {table_name}"
        return execute_delete(query, ())
        
    except Exception as e:
        print(f"[DB ERROR] Clear table failed: {e}")
        return False

def get_database_info() -> Dict:
    """Get database statistics"""
    try:
        tables = ['transactions', 'bills', 'weekly_summaries', 'savings_goals']
        
        info = {
            'database_path': DB_NAME,
            'tables': {}
        }
        
        for table in tables:
            if table_exists(table):
                info['tables'][table] = {
                    'exists': True,
                    'row_count': get_table_row_count(table)
                }
            else:
                info['tables'][table] = {
                    'exists': False,
                    'row_count': 0
                }
        
        return info
        
    except Exception as e:
        print(f"[DB ERROR] Database info failed: {e}")
        return {}

# ============================================================================
# INITIALIZATION CHECK
# ============================================================================

def ensure_database_ready():
    """Ensure database is initialized and ready"""
    try:
        # Check if main tables exist
        required_tables = ['transactions', 'bills']
        
        for table in required_tables:
            if not table_exists(table):
                print(f"[DB] Table '{table}' not found, initializing...")
                init_all_databases()
                return True
        
        print("[DB] ✓ Database ready")
        return True
        
    except Exception as e:
        print(f"[DB ERROR] Database check failed: {e}")
        return False