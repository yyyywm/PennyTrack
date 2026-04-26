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
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Transaction> _transactions = [];
  bool _isLoading = false;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _isToday = true;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChanged);
    _startDate = DateTime(_endDate.year, _endDate.month, _endDate.day);
    _endDate = DateTime(_endDate.year, _endDate.month, _endDate.day,
        23, 59, 59);
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

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final auth = AuthService.instance;
    List<Transaction> items = [];

    if (auth.isLoggedIn) {
      items = await ApiService.getTransactions(
        startDate: _startDate,
        endDate: _endDate,
        limit: 200,
      );
    } else {
      items = await StorageService.loadTodayItems();
    }

    // await 之后 widget 可能已 dispose，必须重新检查 mounted
    if (!mounted) return;
    setState(() {
      _transactions = items;
      _isLoading = false;
    });
  }

  void _setToday() {
    final now = DateTime.now();
    setState(() {
      _isToday = true;
      _startDate = DateTime(now.year, now.month, now.day);
      _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    });
    _loadData();
  }

  void _setMonth() {
    final now = DateTime.now();
    setState(() {
      _isToday = false;
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
        _isToday = false;
        _startDate = DateTime(picked.start.year, picked.start.month,
            picked.start.day);
        _endDate = DateTime(picked.end.year, picked.end.month,
            picked.end.day, 23, 59, 59);
      });
      _loadData();
    }
  }

  Future<void> _addTransaction(Transaction newItem) async {
    final messenger = ScaffoldMessenger.of(context);
    final auth = AuthService.instance;

    if (auth.isLoggedIn) {
      await ApiService.createTransaction(newItem);
      // 登录状态下数据已同步到后端，不再保存到本地缓存，
      // 避免退出登录后再次同步导致重复上传
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

    // 更新本地缓存
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 日期筛选栏
            Row(
              children: [
                ChoiceChip(
                  label: const Text('今日'),
                  selected: _isToday,
                  onSelected: (_) => _setToday(),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('本月'),
                  selected: !_isToday,
                  onSelected: (_) => _setMonth(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.date_range),
                  onPressed: _pickDateRange,
                  tooltip: '自定义日期',
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 收支汇总
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSummaryItem('收入', _totalIncome, Colors.green),
                  _buildSummaryItem('支出', _totalExpense, Colors.red),
                  _buildSummaryItem(
                    '结余',
                    _totalIncome - _totalExpense,
                    _totalIncome >= _totalExpense
                        ? Colors.green
                        : Colors.red,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 标题
            const Text(
              '记账明细',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // 列表
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _transactions.isEmpty
                      ? const Center(child: Text('暂无记录'))
                      : ListView.builder(
                          itemCount: _transactions.length,
                          itemBuilder: (context, index) {
                            final item = _transactions[index];
                            return TransactionCard(
                              transaction: item,
                              onEdit: (updated) => _updateTransaction(updated),
                              onDeleteApi: () => _deleteTransaction(item.id),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 12),

            // 添加按钮
            InkWell(
              onTap: () {
                showAddRecordBottomSheet(
                  context: context,
                  onAdded: _addTransaction,
                );
              },
              borderRadius: BorderRadius.circular(50),
              child: const CircleAvatar(
                backgroundImage:
                    AssetImage('assets/images/record.png'),
                radius: 36,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, double amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
        const SizedBox(height: 4),
        Text(
          '${amount >= 0 ? '+' : ''}${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
