# ============================================================================
# FILE: app/routes/analytics_routes.py
# Expense Analytics API Endpoints
# ============================================================================

"""
Analytics Routes
API endpoints for expense analytics and reporting
"""

from flask import Blueprint, request, jsonify
from datetime import datetime
import traceback
from app.services.expense_analytics_service import ExpenseAnalytics, ReportGenerator

analytics_bp = Blueprint('analytics', __name__, url_prefix='/api/analytics')

@analytics_bp.route('/dashboard', methods=['POST'])
def get_expense_dashboard():
    """
    Get expense dashboard data
    
    Request JSON:
    {
        "period": "daily|weekly|monthly",
        "date": "2025-01-29T00:00:00"
    }
    """
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'error': 'No data provided'
            }), 400
        
        period = data.get('period', 'weekly')
        date_str = data.get('date')
        
        # Validate period
        if period not in ['daily', 'weekly', 'monthly']:
            return jsonify({
                'success': False,
                'error': 'Invalid period. Must be daily, weekly, or monthly'
            }), 400
        
        # Parse date
        try:
            if date_str:
                date = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
            else:
                date = datetime.now()
        except:
            date = datetime.now()
        
        # Get dashboard data
        dashboard_data = ExpenseAnalytics.get_dashboard_data(period, date)
        
        return jsonify({
            'success': True,
            **dashboard_data
        }), 200
    
    except Exception as e:
        print(f"[ANALYTICS ERROR] /dashboard: {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@analytics_bp.route('/report', methods=['POST'])
def generate_expense_report():
    """
    Generate expense report
    
    Request JSON:
    {
        "period": "daily|weekly|monthly",
        "date": "2025-01-29T00:00:00"
    }
    """
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'error': 'No data provided'
            }), 400
        
        period = data.get('period', 'weekly')
        date_str = data.get('date')
        
        # Validate period
        if period not in ['daily', 'weekly', 'monthly']:
            return jsonify({
                'success': False,
                'error': 'Invalid period'
            }), 400
        
        # Parse date
        try:
            if date_str:
                date = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
            else:
                date = datetime.now()
        except:
            date = datetime.now()
        
        # Generate report
        report = ReportGenerator.generate_expense_report(period, date)
        
        return jsonify(report), 200
    
    except Exception as e:
        print(f"[ANALYTICS ERROR] /report: {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@analytics_bp.route('/category/<category>', methods=['GET'])
def get_category_details(category):
    """Get detailed information for a specific category"""
    try:
        period = request.args.get('period', 'weekly')
        date_str = request.args.get('date')
        
        try:
            if date_str:
                date = datetime.fromisoformat(date_str)
            else:
                date = datetime.now()
        except:
            date = datetime.now()
        
        # Get dashboard data
        dashboard_data = ExpenseAnalytics.get_dashboard_data(period, date)
        
        # Find category
        category_data = None
        for cat in dashboard_data['category_breakdown']:
            if cat['category'] == category:
                category_data = cat
                break
        
        if not category_data:
            return jsonify({
                'success': False,
                'error': 'Category not found'
            }), 404
        
        # Get transactions for this category
        category_transactions = [
            t for t in dashboard_data['transactions']
            if t['category'] == category
        ]
        
        return jsonify({
            'success': True,
            'category': category,
            'data': category_data,
            'transactions': category_transactions
        }), 200
    
    except Exception as e:
        print(f"[ANALYTICS ERROR] /category/{category}: {e}")
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500