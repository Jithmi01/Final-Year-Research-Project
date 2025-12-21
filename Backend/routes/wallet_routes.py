# FILE: app/routes/wallet_routes.py
# Wallet transaction and query endpoints
# ============================================================================

"""
Wallet Routes
API endpoints for wallet operations
"""

from flask import Blueprint, request, jsonify
import traceback
from app.services.wallet_service import WalletService, QuestionAnswerer, SummaryGenerator

wallet_bp = Blueprint('wallet', __name__, url_prefix='/api/wallet')

@wallet_bp.route('/transaction', methods=['POST'])
def add_transaction():
    """Add a new transaction"""
    data = request.json
    
    if not data or not all(k in data for k in ['amount', 'type', 'category']):
        return jsonify({'error': 'Missing required fields: amount, type, category'}), 400
    
    try:
        amount = float(data['amount'])
        trans_type = data['type'].lower()
        category = data['category']
        description = data.get('description', '')
        
        # Validate
        if trans_type not in ['income', 'expense']:
            return jsonify({'error': 'Type must be income or expense'}), 400
        
        if amount <= 0:
            return jsonify({'error': 'Amount must be positive'}), 400
        
        # Add transaction
        success = WalletService.add_transaction(amount, trans_type, category, description)
        
        if success:
            return jsonify({
                'success': True,
                'message': 'Transaction added successfully',
                'new_balance': WalletService.get_balance()
            }), 200
        
        return jsonify({'error': 'Failed to add transaction'}), 500
    
    except ValueError:
        return jsonify({'error': 'Invalid amount format'}), 400
    except Exception as e:
        print(f"[API ERROR] /wallet/transaction: {e}")
        traceback.print_exc()
        
        return jsonify({'error': str(e)}), 500


@wallet_bp.route('/balance', methods=['GET'])
def get_balance():
    """Get current balance"""
    try:
        balance = WalletService.get_balance()
        return jsonify({
            'success': True,
            'balance': balance
        }), 200
    
    except Exception as e:
        print(f"[API ERROR] /wallet/balance: {e}")
        return jsonify({'error': str(e)}), 500


@wallet_bp.route('/transactions/recent', methods=['GET'])
def get_recent_transactions():
    """Get recent transactions"""
    try:
        limit = request.args.get('limit', 5, type=int)
        transactions = WalletService.get_recent_transactions(limit)
        
        return jsonify({
            'success': True,
            'transactions': transactions,
            'count': len(transactions)
        }), 200
    
    except Exception as e:
        print(f"[API ERROR] /wallet/transactions/recent: {e}")
        return jsonify({'error': str(e)}), 500


@wallet_bp.route('/question', methods=['POST'])
def ask_question():
    """Answer natural language question about wallet"""
    data = request.json
    
    if not data or 'question' not in data:
        return jsonify({'error': 'Missing question'}), 400
    
    try:
        question = data['question']
        answer = QuestionAnswerer.process_question(question)
        
        return jsonify({
            'success': True,
            'answer': answer
        }), 200
    
    except Exception as e:
        print(f"[API ERROR] /wallet/question: {e}")
        return jsonify({'error': str(e)}), 500


@wallet_bp.route('/summary/weekly', methods=['GET'])
def get_weekly_summary():
    """Get weekly spending summary"""
    try:
        summary = SummaryGenerator.generate_weekly()
        
        return jsonify({
            'success': True,
            **summary
        }), 200
    
    except Exception as e:
        print(f"[API ERROR] /wallet/summary/weekly: {e}")
        return jsonify({'error': str(e)}), 500


@wallet_bp.route('/breakdown', methods=['GET'])
def get_category_breakdown():
    """Get category-wise spending breakdown"""
    try:
        days = request.args.get('days', 7, type=int)
        breakdown = WalletService.get_category_breakdown(days)
        
        return jsonify({
            'success': True,
            'breakdown': breakdown,
            'period_days': days
        }), 200
    
    except Exception as e:
        print(f"[API ERROR] /wallet/breakdown: {e}")
        return jsonify({'error': str(e)}), 500

