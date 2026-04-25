import 'dart:math' show pi;

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

/// 统计页面：单页滚动布局，统一月份导航
class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  bool _isLoading = true;
  SummaryData? _summary;
  CategoryStatsData? _categoryStats;
  TrendsData? _trends;
  DateTime _currentMonth = DateTime.now();

  String get _monthYearString => '${_currentMonth.year}年${_currentMonth.month}月';

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChanged);
    _loadData();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final auth = AuthService.instance;
    if (auth.isLoggedIn) {
      final startOfMonth = DateTime.utc(_currentMonth.year, _currentMonth.month, 1);
      final endOfMonth = DateTime.utc(_currentMonth.year, _currentMonth.month + 1, 1)
          .subtract(const Duration(microseconds: 1));

      final summary = await ApiService.getSummary(
        startDate: startOfMonth,
        endDate: endOfMonth,
      );
      final categoryStats = await ApiService.getCategoryStats(
        startDate: startOfMonth,
        endDate: endOfMonth,
      );
      final trends = await ApiService.getTrends(
        period: 'day',
        year: _currentMonth.year,
        month: _currentMonth.month,
      );

      if (mounted) {
        setState(() {
          _summary = summary;
          _categoryStats = categoryStats;
          _trends = trends;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _summary = null;
          _categoryStats = null;
          _trends = null;
          _isLoading = false;
        });
      }
    }
  }

  void _previousMonth() {
    _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    _loadData();
  }

  void _nextMonth() {
    _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    _loadData();
  }

  Future<void> _showMonthPicker() async {
    int selectedYear = _currentMonth.year;
    int selectedMonth = _currentMonth.month;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('选择月份'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DropdownButton<int>(
                value: selectedYear,
                items: List.generate(5, (i) {
                  final y = DateTime.now().year - i;
                  return DropdownMenuItem(value: y, child: Text('$y年'));
                }),
                onChanged: (y) {
                  if (y != null) setDialogState(() => selectedYear = y);
                },
                underline: Container(height: 1, color: Colors.grey),
              ),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: selectedMonth,
                items: List.generate(12, (i) {
                  final m = i + 1;
                  return DropdownMenuItem(value: m, child: Text('$m月'));
                }),
                onChanged: (m) {
                  if (m != null) setDialogState(() => selectedMonth = m);
                },
                underline: Container(height: 1, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      _currentMonth = DateTime(selectedYear, selectedMonth);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;

    if (!auth.isLoggedIn) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('请先登录后查看统计', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildMonthHeader(),
                  const SizedBox(height: 20),
                  _buildSummarySection(),
                  const SizedBox(height: 24),
                  _buildCategorySection(),
                  const SizedBox(height: 24),
                  _buildTrendsSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ========== 月份导航 ==========
  Widget _buildMonthHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: _previousMonth,
        ),
        GestureDetector(
          onTap: _showMonthPicker,
          child: Text(
            _monthYearString,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _nextMonth,
        ),
      ],
    );
  }

  // ========== 摘要区域 ==========
  Widget _buildSummarySection() {
    if (_summary == null) {
      return const Center(child: Text('暂无数据'));
    }

    final s = _summary!;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                '收入',
                s.income,
                Colors.green,
                Icons.arrow_upward,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSummaryCard(
                '支出',
                s.expense,
                Colors.red,
                Icons.arrow_downward,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSummaryCard(
                '结余',
                s.balance,
                s.balance >= 0 ? Colors.green : Colors.red,
                Icons.account_balance_wallet,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildMoMChip('收入环比', s.incomeChange),
            _buildMoMChip('支出环比', s.expenseChange),
            _buildMoMChip('结余环比', s.balanceChange),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
      String title, double value, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoMChip(String title, double change) {
    final isPositive = change >= 0;
    final color = isPositive ? Colors.green : Colors.red;
    return Column(
      children: [
        Text(title, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPositive ? Icons.arrow_upward : Icons.arrow_downward,
              color: color,
              size: 12,
            ),
            Text(
              '${change.abs().toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ========== 分类区域 ==========
  Widget _buildCategorySection() {
    final hasData = _categoryStats != null && _categoryStats!.labels.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '支出分类',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (!hasData)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.pie_chart_outline, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('暂无分类数据', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          )
        else ...[
          Center(
            child: SizedBox(
              height: 200,
              child: CustomPaint(
                size: const Size(200, 200),
                painter: PieChartPainter(
                  values: _categoryStats!.values,
                  colors: _categoryStats!.colors.map(_colorFromString).toList(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(_categoryStats!.labels.length, (i) {
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                backgroundColor: _colorFromString(_categoryStats!.colors[i]),
                radius: 8,
              ),
              title: Text(_categoryStats!.labels[i]),
              trailing: Text(
                '${_categoryStats!.amounts[i].toStringAsFixed(2)} \uffe5 '
                '(${_categoryStats!.values[i].toStringAsFixed(1)}%)',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            );
          }),
        ],
      ],
    );
  }

  // ========== 趋势区域 ==========
  Widget _buildTrendsSection() {
    final hasData = _trends != null && _trends!.labels.isNotEmpty;
    final hasNonZeroData = hasData &&
        (_trends!.income.any((v) => v > 0) ||
            _trends!.expense.any((v) => v > 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '每日收支',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (!hasNonZeroData)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.show_chart, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text(
                    '该月暂无收支记录',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else ...[
          SizedBox(
            height: 240,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _BarChart(
                  labels: _trends!.labels,
                  incomeData: _trends!.income,
                  expenseData: _trends!.expense,
                  maxValue: [
                    ..._trends!.income,
                    ..._trends!.expense,
                  ].fold<double>(0, (prev, e) => e > prev ? e : prev),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('收入', Colors.green),
              const SizedBox(width: 24),
              _buildLegendItem('支出', Colors.red),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(backgroundColor: color, radius: 6),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }

  Color _colorFromString(String? colorName) {
    final Map<String, Color> colorMap = {
      'green': Colors.green,
      'teal': Colors.teal,
      'emerald': Colors.greenAccent,
      'lime': Colors.lime,
      'cyan': Colors.cyan,
      'blue': Colors.blue,
      'yellow': Colors.yellow,
      'purple': Colors.purple,
      'red': Colors.red,
      'indigo': Colors.indigo,
      'pink': Colors.pink,
      'gray': Colors.grey,
      'orange': Colors.orange,
    };
    return colorMap[colorName?.toLowerCase()] ?? Colors.blue;
  }
}

/// 简易饼图画布
class PieChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;

  PieChartPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, v) => sum + v);
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width < size.height ? size.width / 2 : size.height / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    double startAngle = -pi / 2;
    for (int i = 0; i < values.length; i++) {
      final sweepAngle = (values[i] / total) * 2 * pi;
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.fill;
      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
      startAngle += sweepAngle;
    }

    final holePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.45, holePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 简易柱状图组件（固定宽度，适配横向滚动）
class _BarChart extends StatelessWidget {
  final List<String> labels;
  final List<double> incomeData;
  final List<double> expenseData;
  final double maxValue;

  const _BarChart({
    required this.labels,
    required this.incomeData,
    required this.expenseData,
    required this.maxValue,
  });

  @override
  Widget build(BuildContext context) {
    const double itemWidth = 40;

    return SizedBox(
      width: labels.length * itemWidth,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(labels.length, (i) {
          final incomeRatio = maxValue > 0
              ? (incomeData[i] / maxValue).clamp(0.0, 1.0)
              : 0.0;
          final expenseRatio = maxValue > 0
              ? (expenseData[i] / maxValue).clamp(0.0, 1.0)
              : 0.0;

          return SizedBox(
            width: itemWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 12,
                    height: 100 * incomeRatio,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 12,
                    height: 100 * expenseRatio,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[i],
                    style: const TextStyle(fontSize: 9),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
