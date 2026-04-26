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

  String get _monthYearString =>
      '${_currentMonth.year}年${_currentMonth.month}月';

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
      final startOfMonth =
          DateTime(_currentMonth.year, _currentMonth.month, 1).toUtc();
      final endOfMonth =
          DateTime(_currentMonth.year, _currentMonth.month + 1, 1)
              .subtract(const Duration(microseconds: 1))
              .toUtc();

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
        timezoneOffset: DateTime.now().timeZoneOffset.inMinutes,
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
      return SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 56, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                '请先登录后查看统计',
                style: TextStyle(fontSize: 15, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              _buildPageHeader(),
              const SizedBox(height: 12),
              _buildMonthCapsule(),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              const SizedBox(height: 16),
              Opacity(
                opacity: _isLoading ? 0.5 : 1.0,
                child: _buildSummarySection(),
              ),
              const SizedBox(height: 20),
              Opacity(
                opacity: _isLoading ? 0.5 : 1.0,
                child: _buildCategoryCard(),
              ),
              const SizedBox(height: 20),
              Opacity(
                opacity: _isLoading ? 0.5 : 1.0,
                child: _buildTrendsCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ========== 顶部页面标题 ==========
  Widget _buildPageHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 4, 0, 0),
      child: Text(
        '统计',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
    );
  }

  // ========== 月份导航胶囊 ==========
  Widget _buildMonthCapsule() {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(40),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 22),
              onPressed: _isLoading ? null : _previousMonth,
              visualDensity: VisualDensity.compact,
            ),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _isLoading ? null : _showMonthPicker,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _monthYearString,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down,
                        size: 18, color: Colors.grey[700]),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 22),
              onPressed: _isLoading ? null : _nextMonth,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  // ========== 摘要区域 ==========
  Widget _buildSummarySection() {
    if (_summary == null) {
      return _buildEmptyCard('暂无数据', Icons.insights_outlined);
    }

    final s = _summary!;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                icon: Icons.arrow_upward_rounded,
                label: '收入',
                value: s.income,
                change: s.incomeChange,
                color: Colors.green[700]!,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                icon: Icons.arrow_downward_rounded,
                label: '支出',
                value: s.expense,
                change: s.expenseChange,
                color: Colors.red[700]!,
                invertChange: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildBalanceCard(s),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required double value,
    required double change,
    required Color color,
    bool invertChange = false,
  }) {
    // invertChange: 支出环比上涨视为坏（红），下降视为好（绿）
    final isUp = change >= 0;
    final isGood = invertChange ? !isUp : isUp;
    final changeColor = isGood ? Colors.green[600]! : Colors.red[600]!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                isUp ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: changeColor,
              ),
              Text(
                ' ${change.abs().toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 11,
                  color: changeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '环比',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(SummaryData s) {
    final balanceColor =
        s.balance >= 0 ? Colors.green[700]! : Colors.red[700]!;
    final isUp = s.balanceChange >= 0;
    final changeColor = isUp ? Colors.green[600]! : Colors.red[600]!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.7),
            Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.account_balance_wallet_outlined,
              color: balanceColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本月结余',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '￥${s.balance.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: balanceColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: changeColor.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUp ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12,
                  color: changeColor,
                ),
                const SizedBox(width: 2),
                Text(
                  '${s.balanceChange.abs().toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: changeColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========== 分类卡片 ==========
  Widget _buildCategoryCard() {
    final hasData =
        _categoryStats != null && _categoryStats!.labels.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '支出分类',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          if (!hasData)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.pie_chart_outline,
                        size: 44, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      '暂无分类数据',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Center(
              child: SizedBox(
                height: 180,
                width: 180,
                child: CustomPaint(
                  size: const Size(180, 180),
                  painter: PieChartPainter(
                    values: _categoryStats!.values,
                    colors: _safeColors(_categoryStats!.colors,
                            _categoryStats!.values.length)
                        .map(_colorFromString)
                        .toList(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...List.generate(_categoryStats!.labels.length, (i) {
              final safeColors = _safeColors(
                  _categoryStats!.colors, _categoryStats!.labels.length);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _colorFromString(safeColors[i]),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _categoryStats!.labels[i],
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      '￥${_categoryStats!.amounts[i].toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${_categoryStats!.values[i].toStringAsFixed(1)}%',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ========== 趋势卡片 ==========
  Widget _buildTrendsCard() {
    final hasData = _trends != null && _trends!.labels.isNotEmpty;
    final hasNonZeroData = hasData &&
        (_trends!.income.any((v) => v > 0) ||
            _trends!.expense.any((v) => v > 0));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '每日收支',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              _buildLegendDot('收入', Colors.green[600]!),
              const SizedBox(width: 12),
              _buildLegendDot('支出', Colors.red[600]!),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasNonZeroData)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.show_chart,
                        size: 44, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      '该月暂无收支记录',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 200,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
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
        ],
      ),
    );
  }

  Widget _buildLegendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ],
    );
  }

  Widget _buildEmptyCard(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 44, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(text, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
        ),
      ),
    );
  }

  /// 确保 colors 列表长度与数据项一致，避免数组越界
  List<String> _safeColors(List<String> colors, int targetLength) {
    if (colors.length >= targetLength) {
      return colors.sublist(0, targetLength);
    }
    return [...colors, ...List.filled(targetLength - colors.length, 'blue')];
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
    canvas.drawCircle(center, radius * 0.55, holePaint);
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
    const double maxBarHeight = 130;

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
                    width: 10,
                    height: maxBarHeight * incomeRatio,
                    decoration: BoxDecoration(
                      color: Colors.green[600],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    width: 10,
                    height: maxBarHeight * expenseRatio,
                    decoration: BoxDecoration(
                      color: Colors.red[600],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    style: TextStyle(fontSize: 9, color: Colors.grey[600]),
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
