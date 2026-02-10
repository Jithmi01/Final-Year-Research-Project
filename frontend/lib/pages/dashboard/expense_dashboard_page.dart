// lib/pages/dashboard/expense_dashboard_page.dart
// EXPENSE ANALYTICS DASHBOARD WITH CHARTS & AI ALERTS

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../main.dart';
import '../../widgets/voice_navigation_widget.dart';

class ExpenseDashboardPage extends StatefulWidget {
  const ExpenseDashboardPage({Key? key}) : super(key: key);

  @override
  _ExpenseDashboardPageState createState() => _ExpenseDashboardPageState();
}

class _ExpenseDashboardPageState extends State<ExpenseDashboardPage> {
  FlutterTts flutterTts = FlutterTts();

  // Period selection
  String _selectedPeriod = 'weekly'; // 'daily', 'weekly', 'monthly'
  DateTime _selectedDate = DateTime.now();

  // Data
  bool _isLoading = false;
  Map<String, dynamic> _dashboardData = {};
  List<dynamic> _categoryBreakdown = [];
  List<dynamic> _transactions = [];
  List<dynamic> _alerts = [];
  double _totalSpending = 0.0;
  double _totalIncome = 0.0;

  // Category colors
  final Map<String, Color> _categoryColors = {
    'Health': Color(0xFFE74C3C),
    'Grocery': Color(0xFF27AE60),
    'Dining': Color(0xFFF39C12),
    'Transport': Color(0xFF3498DB),
    'Utilities': Color(0xFF9B59B6),
    'Shopping': Color(0xFFE91E63),
    'Entertainment': Color(0xFFFF5722),
    'Education': Color(0xFF2196F3),
    'Personal Care': Color(0xFFFF9800),
    'Home & Garden': Color(0xFF8BC34A),
    'General': Color(0xFF95A5A6),
  };

  // Category icons
  final Map<String, IconData> _categoryIcons = {
    'Health': Icons.medical_services,
    'Grocery': Icons.shopping_cart,
    'Dining': Icons.restaurant,
    'Transport': Icons.directions_car,
    'Utilities': Icons.lightbulb,
    'Shopping': Icons.shopping_bag,
    'Entertainment': Icons.movie,
    'Education': Icons.school,
    'Personal Care': Icons.spa,
    'Home & Garden': Icons.home,
    'General': Icons.category,
  };

  @override
  void initState() {
    super.initState();
    _setupTts();
    _loadDashboardData();
  }

  void _setupTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    await flutterTts.stop();
    await flutterTts.speak(text);
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse("$API_URL/get_expense_dashboard"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'period': _selectedPeriod,
          'date': _selectedDate.toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        if (mounted) {
          setState(() {
            _dashboardData = data;
            _categoryBreakdown = data['category_breakdown'] ?? [];
            _transactions = data['transactions'] ?? [];
            _alerts = data['alerts'] ?? [];
            _totalSpending = (data['total_spending'] ?? 0.0).toDouble();
            _totalIncome = (data['total_income'] ?? 0.0).toDouble();
          });

          // Announce new alerts
          if (_alerts.isNotEmpty) {
            String alertMessage = _alerts[0]['message'];
            _speak(alertMessage);
          }
        }
      }
    } catch (e) {
      print("[DASHBOARD ERROR] $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load dashboard data'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _generateReport() async {
    _speak("Generating report");

    try {
      final response = await http.post(
        Uri.parse("$API_URL/generate_expense_report"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'period': _selectedPeriod,
          'date': _selectedDate.toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        String reportUrl = data['report_url'];

        _speak("Report generated successfully");

        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.description, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Report Generated'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your expense report has been generated successfully.'),
                  SizedBox(height: 16),
                  Text(
                    'Period: ${_getPeriodText()}',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('Total Spending: Rs.${_totalSpending.toStringAsFixed(2)}'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Close'),
                ),
                ElevatedButton.icon(
                  icon: Icon(Icons.download),
                  label: Text('Download'),
                  onPressed: () {
                    // TODO: Implement download functionality
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      print("[REPORT ERROR] $e");
      _speak("Failed to generate report");
    }
  }

  String _getPeriodText() {
    switch (_selectedPeriod) {
      case 'daily':
        return DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate);
      case 'weekly':
        DateTime weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
        DateTime weekEnd = weekStart.add(Duration(days: 6));
        return '${DateFormat('MMM d').format(weekStart)} - ${DateFormat('MMM d, yyyy').format(weekEnd)}';
      case 'monthly':
        return DateFormat('MMMM yyyy').format(_selectedDate);
      default:
        return '';
    }
  }

  void _changePeriod(String period) {
    setState(() {
      _selectedPeriod = period;
    });
    _speak("Showing ${period} expenses");
    _loadDashboardData();
  }

  void _changeDate(int direction) {
    setState(() {
      switch (_selectedPeriod) {
        case 'daily':
          _selectedDate = _selectedDate.add(Duration(days: direction));
          break;
        case 'weekly':
          _selectedDate = _selectedDate.add(Duration(days: 7 * direction));
          break;
        case 'monthly':
          _selectedDate = DateTime(
            _selectedDate.year,
            _selectedDate.month + direction,
            _selectedDate.day,
          );
          break;
      }
    });
    _loadDashboardData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Expense Dashboard'),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: VoiceNavigationWidget(currentPage: 'expense_dashboard'),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // Period Selector
                    _buildPeriodSelector(),

                    // AI Alerts (if any)
                    if (_alerts.isNotEmpty) _buildAlertsSection(),

                    // Summary Cards
                    _buildSummaryCards(),

                    // Category Breakdown Chart
                    _buildCategoryChart(),

                    // Category Details List
                    _buildCategoryDetailsList(),

                    // Recent Transactions
                    _buildRecentTransactions(),

                    SizedBox(height: 80),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generateReport,
        icon: Icon(Icons.description),
        label: Text('Generate Report'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: EdgeInsets.all(16),
      color: Colors.blue.shade50,
      child: Column(
        children: [
          // Period buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPeriodButton('Daily', 'daily'),
              SizedBox(width: 8),
              _buildPeriodButton('Weekly', 'weekly'),
              SizedBox(width: 8),
              _buildPeriodButton('Monthly', 'monthly'),
            ],
          ),

          SizedBox(height: 12),

          // Date navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left),
                onPressed: () => _changeDate(-1),
              ),
              SizedBox(width: 16),
              Text(
                _getPeriodText(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 16),
              IconButton(
                icon: Icon(Icons.chevron_right),
                onPressed: () => _changeDate(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodButton(String label, String value) {
    bool isSelected = _selectedPeriod == value;

    return ElevatedButton(
      onPressed: () => _changePeriod(value),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue : Colors.white,
        foregroundColor: isSelected ? Colors.white : Colors.blue,
        elevation: isSelected ? 4 : 1,
      ),
      child: Text(label),
    );
  }

  Widget _buildAlertsSection() {
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade400, Colors.red.shade400],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.white, size: 28),
              SizedBox(width: 8),
              Text(
                'AI Alerts',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          ..._alerts.map((alert) {
            return Container(
              margin: EdgeInsets.only(bottom: 8),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alert['message'],
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    double balance = _totalIncome - _totalSpending;

    return Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryCard(
              'Total Spending',
              'Rs.${_totalSpending.toStringAsFixed(2)}',
              Icons.trending_down,
              Colors.red,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _buildSummaryCard(
              'Total Income',
              'Rs.${_totalIncome.toStringAsFixed(2)}',
              Icons.trending_up,
              Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChart() {
    if (_categoryBreakdown.isEmpty) {
      return Container(
        margin: EdgeInsets.all(16),
        padding: EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'No expense data for this period',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spending by Category',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 24),
          SizedBox(
            height: 250,
            child: PieChart(
              PieChartData(
                sections: _buildPieChartSections(),
                sectionsSpace: 2,
                centerSpaceRadius: 60,
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildPieChartSections() {
    return _categoryBreakdown.map((item) {
      String category = item['category'];
      double amount = (item['amount'] ?? 0.0).toDouble();
      double percentage = (item['percentage'] ?? 0.0).toDouble();

      Color color = _categoryColors[category] ?? Colors.grey;

      return PieChartSectionData(
        color: color,
        value: amount,
        title: '${percentage.toStringAsFixed(1)}%',
        radius: 80,
        titleStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  Widget _buildCategoryDetailsList() {
    if (_categoryBreakdown.isEmpty) {
      return SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Category Breakdown',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: _categoryBreakdown.length,
            separatorBuilder: (context, index) => Divider(height: 24),
            itemBuilder: (context, index) {
              var item = _categoryBreakdown[index];
              String category = item['category'];
              double amount = (item['amount'] ?? 0.0).toDouble();
              double percentage = (item['percentage'] ?? 0.0).toDouble();
              int transactionCount = item['transaction_count'] ?? 0;

              Color color = _categoryColors[category] ?? Colors.grey;
              IconData icon = _categoryIcons[category] ?? Icons.category;

              return Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '$transactionCount transactions',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percentage / 100,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Rs.${amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions() {
    if (_transactions.isEmpty) {
      return SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Transactions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: _transactions.length > 5 ? 5 : _transactions.length,
            separatorBuilder: (context, index) => Divider(height: 16),
            itemBuilder: (context, index) {
              var transaction = _transactions[index];
              String type = transaction['type'];
              double amount = (transaction['amount'] ?? 0.0).toDouble();
              String category = transaction['category'] ?? 'General';
              String description = transaction['description'] ?? '';
              String date = transaction['date'] ?? '';

              Color color = type == 'income' ? Colors.green : Colors.red;
              IconData icon = _categoryIcons[category] ?? Icons.category;

              return Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          description.isNotEmpty ? description : category,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4),
                        Text(
                          date.isNotEmpty
                              ? DateFormat('MMM d, yyyy').format(DateTime.parse(date))
                              : '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${type == 'expense' ? '-' : '+'}Rs.${amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}