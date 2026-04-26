import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../widgets/add_record_sheet.dart';
import '../widgets/transaction_card.dart';

/// 首页：展示记账列表
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

/// 公开 State 以便 NavigatePage 通过 GlobalKey 调用 [openAddSheet]
class HomePageState extends State<HomePage> {
  List<Transaction> _transactions = [];
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  /// 0=今日 1=本月 2=自定义
  int _rangeMode = 0;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChanged);
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _loadData();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) {
      _loadData();
    }
  }

  /// 公开接口：从外部（导航 FAB）触发添加记录弹窗
  void openAddSheet() {
    showAddRecordBottomSheet(
      context: context,
      onAdded: _addTransaction,
    );
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    final auth = AuthService.instance;
    List<Transaction> items = [];

    try {
      if (auth.isLoggedIn) {
        items = await ApiService.getTransactions(
          startDate: _startDate,
          endDate: _endDate,
          limit: 200,
        );
      } else {
        items = await StorageService.loadTodayItems();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }

    if (!mounted) return;
    setState(() {
      _transactions = items;
      _isLoading = false;
    });
  }

  void _setToday() {
    final now = DateTime.now();
    setState(() {
      _rangeMode = 0;
      _startDate = DateTime(now.year, now.month, now.day);
      _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    });
    _loadData();
  }

  void _setMonth() {
    final now = DateTime.now();
    setState(() {
      _rangeMode = 1;
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    });
    _loadData();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      if (!mounted) return;
      setState(() {
        _rangeMode = 2;
        _startDate = DateTime(
            picked.start.year, picked.start.month, picked.start.day);
        _endDate = DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
      _loadData();
    }
  }

  Future<void> _addTransaction(Transaction newItem) async {
    final messenger = ScaffoldMessenger.of(context);
    final auth = AuthService.instance;

    if (auth.isLoggedIn) {
      await ApiService.createTransaction(newItem);
    } else {
      await StorageService.addItem(newItem);
    }

    await _loadData();

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('添加成功: ${newItem.displayPrice}')),
    );
  }

  Future<void> _updateTransaction(Transaction updated) async {
    final messenger = ScaffoldMessenger.of(context);
    final auth = AuthService.instance;

    if (auth.isLoggedIn) {
      await ApiService.updateTransaction(updated.id, updated);
    }

    final localItems = await StorageService.loadTodayItems();
    final index = localItems.indexWhere((t) => t.id == updated.id);
    if (index >= 0) {
      localItems[index] = updated;
      await StorageService.saveTodayItems(localItems);
    }

    await _loadData();

    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('更新成功')),
    );
  }

  Future<void> _deleteTransaction(String id) async {
    final auth = AuthService.instance;
    final messenger = ScaffoldMessenger.of(context);

    if (auth.isLoggedIn) {
      final success = await ApiService.deleteTransaction(id);
      if (!success && mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('后端删除失败，已移除本地记录')),
        );
      }
    }
    await StorageService.deleteItemById(id);
    await _loadData();
  }

  double get _totalIncome {
    return _transactions
        .where((t) => t.isIncome)
        .fold(0, (sum, t) => sum + t.amount);
  }

  double get _totalExpense {
    return _transactions
        .where((t) => !t.isIncome)
        .fold(0, (sum, t) => sum + t.amount);
  }

  String get _rangeLabel {
    switch (_rangeMode) {
      case 0:
        return '今日结余';
      case 1:
        return '本月结余';
      default:
        final s = _startDate;
        final e = _endDate;
        final sameDay =
            s.year == e.year && s.month == e.month && s.day == e.day;
        if (sameDay) {
          return '${s.month}.${s.day} 结余';
        }
        return '${s.month}.${s.day} - ${e.month}.${e.day} 结余';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _buildSummaryHero(),
            ),
            const SizedBox(height: 16),
            _buildFilterBar(),
            const SizedBox(height: 8),
            _buildListHeader(),
            const SizedBox(height: 4),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadData,
                child: _buildList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== 顶部页面标题 ==========
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          const Text(
            '记一笔',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.event_note_outlined),
            onPressed: _pickDateRange,
            tooltip: '自定义日期',
          ),
        ],
      ),
    );
  }

  // ========== 汇总大卡片 ==========
  Widget _buildSummaryHero() {
    final cs = Theme.of(context).colorScheme;
    final balance = _totalIncome - _totalExpense;
    final balanceColor = balance >= 0 ? Colors.black87 : Colors.red[700]!;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer,
            cs.secondaryContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _rangeLabel,
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.55),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '￥',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: balanceColor,
                ),
              ),
              const SizedBox(width: 2),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    balance.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: balanceColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildSummaryEntry(
                  Icons.arrow_upward_rounded,
                  '收入',
                  _totalIncome,
                  Colors.green[700]!,
                ),
              ),
              Container(
                width: 1,
                height: 32,
                color: Colors.black.withValues(alpha: 0.06),
              ),
              Expanded(
                child: _buildSummaryEntry(
                  Icons.arrow_downward_rounded,
                  '支出',
                  _totalExpense,
                  Colors.red[700]!,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryEntry(
      IconData icon, String label, double amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amount.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========== 筛选栏 ==========
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SegmentedButton<int>(
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: const [
          ButtonSegment(value: 0, label: Text('今日')),
          ButtonSegment(value: 1, label: Text('本月')),
          ButtonSegment(value: 2, label: Text('自定义')),
        ],
        selected: {_rangeMode},
        showSelectedIcon: false,
        onSelectionChanged: (set) {
          final v = set.first;
          if (v == 0) {
            _setToday();
          } else if (v == 1) {
            _setMonth();
          } else {
            _pickDateRange();
          }
        },
      ),
    );
  }

  // ========== 明细标题 ==========
  Widget _buildListHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Text(
        '明细 · ${_transactions.length} 笔',
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[600],
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  // ========== 列表 ==========
  Widget _buildList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasError) return _buildErrorView();
    if (_transactions.isEmpty) return _buildEmptyView();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final item = _transactions[index];
        return TransactionCard(
          transaction: item,
          onEdit: (updated) => _updateTransaction(updated),
          onDeleteApi: () => _deleteTransaction(item.id),
        );
      },
    );
  }

  Widget _buildEmptyView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 60),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 56, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                '暂无记录',
                style: TextStyle(fontSize: 15, color: Colors.grey[700]),
              ),
              const SizedBox(height: 4),
              Text(
                '点击右下角按钮添加一笔',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 60),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 56, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                '加载失败',
                style: TextStyle(fontSize: 15, color: Colors.grey[700]),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
