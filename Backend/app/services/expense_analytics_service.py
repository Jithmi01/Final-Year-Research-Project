# ============================================================================
# FILE: app/services/expense_analytics_service.py
# Expense Analytics & AI Alert Generation Service
# ============================================================================

"""
Expense Analytics Service
Provides spending insights, category breakdowns, and AI-powered alerts
"""

from datetime import datetime, timedelta
from typing import Dict, List, Tuple
from config import Config
import statistics

# Import based on database type
if Config.DATABASE_TYPE == 'firebase':
    from app.models import firebase_database as db
else:
    from app.models.database import execute_query

# ============================================================================
# EXPENSE ANALYTICS
# ============================================================================

class ExpenseAnalytics:
    """Analyze spending patterns and generate insights"""
    
    # Alert thresholds
    UNUSUAL_SPENDING_THRESHOLD = 1.5  # 150% of average
    HIGH_SPENDING_THRESHOLD = 0.7     # 70% of income
    CATEGORY_SPIKE_THRESHOLD = 2.0    # 200% of category average
    
    @staticmethod
    def get_dashboard_data(period: str, date: datetime) -> Dict:
        """
        Get comprehensive dashboard data
        
        Args:
            period: 'daily', 'weekly', or 'monthly'
            date: Reference date
        
        Returns:
            Dashboard data dictionary
        """
        print(f"[ANALYTICS] Generating dashboard for {period} period")
        
        # Calculate date range
        start_date, end_date = ExpenseAnalytics._get_date_range(period, date)
        
        # Get transactions
        transactions = ExpenseAnalytics._get_transactions(start_date, end_date)
        
        # Calculate totals
        total_spending = sum(t['amount'] for t in transactions if t['type'] == 'expense')
        total_income = sum(t['amount'] for t in transactions if t['type'] == 'income')
        
        # Get category breakdown
        category_breakdown = ExpenseAnalytics._get_category_breakdown(transactions)
        
        # Generate AI alerts
        alerts = ExpenseAnalytics._generate_alerts(
            period, start_date, end_date, 
            total_spending, total_income, 
            category_breakdown
        )
        
        dashboard_data = {
            'period': period,
            'start_date': start_date.isoformat(),
            'end_date': end_date.isoformat(),
            'total_spending': total_spending,
            'total_income': total_income,
            'balance': total_income - total_spending,
            'category_breakdown': category_breakdown,
            'transactions': transactions[:20],  # Recent 20
            'alerts': alerts,
            'transaction_count': len(transactions),
        }
        
        print(f"[ANALYTICS] ✓ Dashboard generated: {len(transactions)} transactions, {len(alerts)} alerts")
        return dashboard_data
    
    @staticmethod
    def _get_date_range(period: str, date: datetime) -> Tuple[datetime, datetime]:
        """Calculate start and end dates for period"""
        if period == 'daily':
            start_date = date.replace(hour=0, minute=0, second=0, microsecond=0)
            end_date = date.replace(hour=23, minute=59, second=59)
        
        elif period == 'weekly':
            # Start from Monday
            start_date = date - timedelta(days=date.weekday())
            start_date = start_date.replace(hour=0, minute=0, second=0, microsecond=0)
            end_date = start_date + timedelta(days=6, hours=23, minutes=59, seconds=59)
        
        elif period == 'monthly':
            start_date = date.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
            # Last day of month
            if date.month == 12:
                end_date = date.replace(year=date.year + 1, month=1, day=1) - timedelta(days=1)
            else:
                end_date = date.replace(month=date.month + 1, day=1) - timedelta(days=1)
            end_date = end_date.replace(hour=23, minute=59, second=59)
        
        else:
            # Default to weekly
            start_date = date - timedelta(days=7)
            end_date = date
        
        return start_date, end_date
    
    @staticmethod
    def _get_transactions(start_date: datetime, end_date: datetime) -> List[Dict]:
        """Get transactions for date range"""
        try:
            if Config.DATABASE_TYPE == 'firebase':
                return db.get_transactions_by_date_range(start_date, end_date)
            else:
                # SQLite version
                query = '''
                    SELECT date, type, amount, category, description
                    FROM transactions
                    WHERE date >= ? AND date <= ?
                    ORDER BY date DESC
                '''
                
                start_str = start_date.strftime("%Y-%m-%d %H:%M:%S")
                end_str = end_date.strftime("%Y-%m-%d %H:%M:%S")
                
                result = execute_query(query, (start_str, end_str))
                
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
            print(f"[ANALYTICS ERROR] Get transactions: {e}")
            return []
    
    @staticmethod
    def _get_category_breakdown(transactions: List[Dict]) -> List[Dict]:
        """Calculate spending breakdown by category"""
        # Get expenses only
        expenses = [t for t in transactions if t['type'] == 'expense']
        
        if not expenses:
            return []
        
        # Group by category
        category_totals = {}
        category_counts = {}
        
        for expense in expenses:
            category = expense['category']
            amount = expense['amount']
            
            if category in category_totals:
                category_totals[category] += amount
                category_counts[category] += 1
            else:
                category_totals[category] = amount
                category_counts[category] = 1
        
        # Calculate total for percentages
        total_spending = sum(category_totals.values())
        
        # Build breakdown list
        breakdown = []
        for category, amount in category_totals.items():
            percentage = (amount / total_spending * 100) if total_spending > 0 else 0
            
            breakdown.append({
                'category': category,
                'amount': amount,
                'percentage': percentage,
                'transaction_count': category_counts[category]
            })
        
        # Sort by amount (descending)
        breakdown.sort(key=lambda x: x['amount'], reverse=True)
        
        return breakdown
    
    @staticmethod
    def _generate_alerts(period: str, start_date: datetime, end_date: datetime,
                        total_spending: float, total_income: float,
                        category_breakdown: List[Dict]) -> List[Dict]:
        """Generate AI-powered spending alerts"""
        alerts = []
        
        # Alert 1: High spending relative to income
        if total_income > 0:
            spending_ratio = total_spending / total_income
            if spending_ratio >= ExpenseAnalytics.HIGH_SPENDING_THRESHOLD:
                alerts.append({
                    'type': 'high_spending',
                    'severity': 'warning',
                    'message': f'Your expenses are {int(spending_ratio * 100)}% of your income this {period}. Consider reducing spending.',
                    'icon': '⚠️'
                })
        
        # Alert 2: Unusual category spending
        for category_data in category_breakdown:
            category = category_data['category']
            current_amount = category_data['amount']
            
            # Get historical average for this category
            avg_amount = ExpenseAnalytics._get_category_average(
                category, period, start_date
            )
            
            if avg_amount > 0 and current_amount >= avg_amount * ExpenseAnalytics.CATEGORY_SPIKE_THRESHOLD:
                increase_pct = int((current_amount / avg_amount - 1) * 100)
                alerts.append({
                    'type': 'category_spike',
                    'severity': 'info',
                    'category': category,
                    'message': f'Your {category} expenses are unusually high this {period}. Up {increase_pct}% from average.',
                    'icon': '📊'
                })
        
        # Alert 3: Top spending category
        if category_breakdown:
            top_category = category_breakdown[0]
            if top_category['percentage'] >= 40:
                alerts.append({
                    'type': 'dominant_category',
                    'severity': 'info',
                    'category': top_category['category'],
                    'message': f'{top_category["category"]} accounts for {int(top_category["percentage"])}% of your spending.',
                    'icon': '📌'
                })
        
        # Alert 4: No income detected
        if total_spending > 0 and total_income == 0:
            alerts.append({
                'type': 'no_income',
                'severity': 'warning',
                'message': f'No income recorded this {period} but you have expenses.',
                'icon': '⚠️'
            })
        
        # Alert 5: Overall spending increase
        previous_start, previous_end = ExpenseAnalytics._get_previous_period(
            period, start_date, end_date
        )
        previous_spending = ExpenseAnalytics._get_total_spending(previous_start, previous_end)
        
        if previous_spending > 0:
            change_pct = ((total_spending - previous_spending) / previous_spending) * 100
            
            if change_pct >= 30:
                alerts.append({
                    'type': 'spending_increase',
                    'severity': 'warning',
                    'message': f'Your spending increased by {int(change_pct)}% compared to last {period}.',
                    'icon': '📈'
                })
            elif change_pct <= -30:
                alerts.append({
                    'type': 'spending_decrease',
                    'severity': 'positive',
                    'message': f'Great job! Your spending decreased by {int(abs(change_pct))}% compared to last {period}.',
                    'icon': '🎉'
                })
        
        return alerts
    
    @staticmethod
    def _get_category_average(category: str, period: str, current_start: datetime) -> float:
        """Get historical average spending for a category"""
        try:
            # Look back 4 periods
            lookback_periods = 4
            amounts = []
            
            for i in range(1, lookback_periods + 1):
                if period == 'daily':
                    period_start = current_start - timedelta(days=i)
                    period_end = period_start + timedelta(days=1)
                elif period == 'weekly':
                    period_start = current_start - timedelta(weeks=i)
                    period_end = period_start + timedelta(weeks=1)
                elif period == 'monthly':
                    # Go back i months
                    year = current_start.year
                    month = current_start.month - i
                    while month <= 0:
                        month += 12
                        year -= 1
                    period_start = datetime(year, month, 1)
                    if month == 12:
                        period_end = datetime(year + 1, 1, 1)
                    else:
                        period_end = datetime(year, month + 1, 1)
                else:
                    break
                
                # Get spending for this period
                if Config.DATABASE_TYPE == 'firebase':
                    transactions = db.get_transactions_by_date_range(period_start, period_end)
                else:
                    query = '''
                        SELECT SUM(amount)
                        FROM transactions
                        WHERE type = 'expense' 
                        AND category = ? 
                        AND date >= ? AND date <= ?
                    '''
                    result = execute_query(query, (
                        category,
                        period_start.strftime("%Y-%m-%d %H:%M:%S"),
                        period_end.strftime("%Y-%m-%d %H:%M:%S")
                    ))
                    
                    if result and result[0][0]:
                        amounts.append(result[0][0])
                        continue
                    
                    transactions = []
                
                category_expenses = [
                    t['amount'] for t in transactions 
                    if t['type'] == 'expense' and t['category'] == category
                ]
                
                if category_expenses:
                    amounts.append(sum(category_expenses))
            
            # Return average
            if amounts:
                return statistics.mean(amounts)
            return 0.0
            
        except Exception as e:
            print(f"[ANALYTICS ERROR] Get category average: {e}")
            return 0.0
    
    @staticmethod
    def _get_previous_period(period: str, start_date: datetime, 
                            end_date: datetime) -> Tuple[datetime, datetime]:
        """Get previous period dates"""
        if period == 'daily':
            previous_start = start_date - timedelta(days=1)
            previous_end = end_date - timedelta(days=1)
        elif period == 'weekly':
            previous_start = start_date - timedelta(weeks=1)
            previous_end = end_date - timedelta(weeks=1)
        elif period == 'monthly':
            # Previous month
            if start_date.month == 1:
                previous_start = start_date.replace(year=start_date.year - 1, month=12)
            else:
                previous_start = start_date.replace(month=start_date.month - 1)
            
            # End of previous month
            previous_end = start_date - timedelta(days=1)
            previous_end = previous_end.replace(hour=23, minute=59, second=59)
        else:
            previous_start = start_date - timedelta(days=7)
            previous_end = end_date - timedelta(days=7)
        
        return previous_start, previous_end
    
    @staticmethod
    def _get_total_spending(start_date: datetime, end_date: datetime) -> float:
        """Get total spending for period"""
        try:
            if Config.DATABASE_TYPE == 'firebase':
                return db.get_total_by_type('expense', start_date, end_date)
            else:
                query = '''
                    SELECT SUM(amount)
                    FROM transactions
                    WHERE type = 'expense'
                    AND date >= ? AND date <= ?
                '''
                
                result = execute_query(query, (
                    start_date.strftime("%Y-%m-%d %H:%M:%S"),
                    end_date.strftime("%Y-%m-%d %H:%M:%S")
                ))
                
                if result and result[0][0]:
                    return result[0][0]
                return 0.0
                
        except Exception as e:
            print(f"[ANALYTICS ERROR] Get total spending: {e}")
            return 0.0

# ============================================================================
# REPORT GENERATOR
# ============================================================================

class ReportGenerator:
    """Generate expense reports"""
    
    @staticmethod
    def generate_expense_report(period: str, date: datetime) -> Dict:
        """
        Generate detailed expense report
        
        Returns:
            Report data with file path
        """
        print(f"[REPORT] Generating {period} report")
        
        # Get dashboard data
        dashboard_data = ExpenseAnalytics.get_dashboard_data(period, date)
        
        # Format report
        report = {
            'title': f'{period.capitalize()} Expense Report',
            'period': f"{dashboard_data['start_date']} to {dashboard_data['end_date']}",
            'generated_at': datetime.now().isoformat(),
            'summary': {
                'total_spending': dashboard_data['total_spending'],
                'total_income': dashboard_data['total_income'],
                'balance': dashboard_data['balance'],
                'transaction_count': dashboard_data['transaction_count']
            },
            'category_breakdown': dashboard_data['category_breakdown'],
            'alerts': dashboard_data['alerts'],
            'transactions': dashboard_data['transactions']
        }
        
        print(f"[REPORT] ✓ Report generated")
        
        return {
            'success': True,
            'report_data': report,
            'report_url': '/reports/expense_report.pdf'  # TODO: Generate actual PDF
        }