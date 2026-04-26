import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/icon_utils.dart';
import '../utils/toast_utils.dart';

/// 底部弹窗：添加或编辑记账记录
class AddRecordSheet extends StatefulWidget {
  final void Function(Transaction newItem) onAdded;
  final Transaction? transaction;

  const AddRecordSheet({super.key, required this.onAdded, this.transaction});

  @override
  State<AddRecordSheet> createState() => _AddRecordSheetState();
}

class _AddRecordSheetState extends State<AddRecordSheet> {
  final _amountController = TextEditingController();
  final _nameController = TextEditingController();
  Category? _selectedCategory;
  bool _isIncome = false;
  DateTime _selectedDate = DateTime.now();
  List<Category> _categories = [];
  bool _isLoadingCategories = false;

  bool get _isEdit => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    _loadCategories();

    if (_isEdit) {
      final t = widget.transaction!;
      _amountController.text = t.amount.toStringAsFixed(2);
      _nameController.text = t.name;
      _isIncome = t.isIncome;
      _selectedDate = t.date;
    }
  }

  Future<void> _loadCategories() async {
    if (!mounted) return;
    setState(() => _isLoadingCategories = true);

    final auth = AuthService.instance;
    List<Category> cats = [];

    if (auth.isLoggedIn) {
      cats = await ApiService.getCategories();
    } else {
      cats = _defaultCategories();
    }

    if (!mounted) return;

    // 如果是编辑模式，尝试选中当前分类
    if (_isEdit && widget.transaction != null) {
      final t = widget.transaction!;
      final matched = cats.firstWhere(
        (c) => c.name == t.type || c.id == t.categoryId,
        orElse: () => cats.isNotEmpty ? cats.first : _fallbackCategory(),
      );
      _selectedCategory = matched;
    }

    setState(() {
      _categories = cats;
      _isLoadingCategories = false;
    });
  }

  /// 离线时使用的默认分类，与后端 `create_user` 中的种子数据保持一致，
  /// 这样登录后同步本地交易时按名称查找能精准命中后端分类。
  /// id 仅作为本地下拉选择标识，登录后会被忽略并按名称重新映射到后端真实 ID。
  List<Category> _defaultCategories() {
    return [
      // 收入
      Category(id: -1, name: '工资', type: 'income', icon: 'fa-money', color: 'green'),
      Category(id: -2, name: '兼职', type: 'income', icon: 'fa-briefcase', color: 'teal'),
      Category(id: -3, name: '投资', type: 'income', icon: 'fa-line-chart', color: 'emerald'),
      Category(id: -4, name: '礼金', type: 'income', icon: 'fa-gift', color: 'lime'),
      Category(id: -5, name: '其他', type: 'income', icon: 'fa-ellipsis-h', color: 'cyan'),
      // 支出
      Category(id: -6, name: '餐饮', type: 'expense', icon: 'fa-cutlery', color: 'blue'),
      Category(id: -7, name: '交通', type: 'expense', icon: 'fa-car', color: 'green'),
      Category(id: -8, name: '购物', type: 'expense', icon: 'fa-shopping-bag', color: 'yellow'),
      Category(id: -9, name: '住房', type: 'expense', icon: 'fa-home', color: 'purple'),
      Category(id: -10, name: '娱乐', type: 'expense', icon: 'fa-film', color: 'red'),
      Category(id: -11, name: '医疗', type: 'expense', icon: 'fa-medkit', color: 'indigo'),
      Category(id: -12, name: '教育', type: 'expense', icon: 'fa-book', color: 'pink'),
      Category(id: -13, name: '其他', type: 'expense', icon: 'fa-ellipsis-h', color: 'gray'),
    ];
  }

  Category _fallbackCategory() {
    return Category(id: -13, name: '其他', type: 'expense', icon: 'fa-ellipsis-h', color: 'gray');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 手柄
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Theme.of(context).dividerColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 标题
                    Text(
                      _isEdit ? '✏️ 编辑记录' : '➕ 添加新记录',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // 名称输入
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: '名称/备注',
                        prefixIcon: const Icon(Icons.description),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 金额输入
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '金额（￥）',
                        prefixIcon: const Icon(Icons.attach_money),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 类型选择
                    _isLoadingCategories
                        ? const Center(child: CircularProgressIndicator())
                        : DropdownButtonFormField<Category>(
                            key: ValueKey(_selectedCategory?.id ?? 'null_$_isIncome'),
                            hint: const Text('选择分类'),
                            initialValue: _selectedCategory,
                            decoration: InputDecoration(
                              labelText: '分类',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: _categories
                                .where((c) =>
                                    (_isIncome && c.type == 'income') ||
                                    (!_isIncome && c.type == 'expense'))
                                .map((category) {
                              return DropdownMenuItem<Category>(
                                value: category,
                                child: Row(
                                  children: [
                                    Icon(
                                      iconNameToIconData(category.icon, _isIncome),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(category.name),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) =>
                                setState(() => _selectedCategory = value),
                          ),
                    const SizedBox(height: 16),

                    // 日期选择
                    ListTile(
                      title: Text(
                        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      subtitle: const Text('点击选择日期'),
                      trailing: const Icon(Icons.calendar_today),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(width: 1.0),
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // 收入/支出 单选
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _isIncome
                                  ? Colors.green[100]
                                  : null,
                              side: BorderSide(
                                color: _isIncome
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _isIncome = true;
                                _selectedCategory = null;
                              });
                            },
                            child: const Text('收入',
                                style: TextStyle(color: Colors.green)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: !_isIncome
                                  ? Colors.red[100]
                                  : null,
                              side: BorderSide(
                                color: !_isIncome
                                    ? Colors.red
                                    : Colors.grey,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _isIncome = false;
                                _selectedCategory = null;
                              });
                            },
                            child: const Text('支出',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 按钮区
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[300],
                              foregroundColor: Colors.black87,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _submit,
                            child: Text(_isEdit ? '保存' : '确定'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _submit() {
    if (_amountController.text.isEmpty || _selectedCategory == null) {
      showCenterToast(
        context: context,
        message: '请填写金额并选择分类',
        icon: Icons.error_outline,
        backgroundColor: const Color.fromARGB(255, 227, 43, 43),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      showCenterToast(
        context: context,
        message: '请输入有效的正数金额',
        icon: Icons.error_outline,
        backgroundColor: const Color.fromARGB(255, 227, 43, 43),
      );
      return;
    }
    if (amount > 99999999.99) {
      showCenterToast(
        context: context,
        message: '金额过大，请重新输入',
        icon: Icons.error_outline,
        backgroundColor: const Color.fromARGB(255, 227, 43, 43),
      );
      return;
    }

    final name = _nameController.text.trim().isEmpty
        ? _selectedCategory!.name
        : _nameController.text.trim();

    final newItem = Transaction(
      id: _isEdit
          ? widget.transaction!.id
          : DateTime.now().millisecondsSinceEpoch.toString(),
      iconCodePoint: iconNameToCodePoint(_selectedCategory!.icon, _isIncome),
      name: name,
      amount: amount,
      type: _selectedCategory!.name,
      isIncome: _isIncome,
      date: _selectedDate,
      categoryId: _selectedCategory!.id,
    );

    widget.onAdded(newItem);
    Navigator.pop(context);
  }

}

/// 显示添加/编辑记账记录的底部弹窗
void showAddRecordBottomSheet({
  required BuildContext context,
  required void Function(Transaction newItem) onAdded,
  Transaction? transaction,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color.fromARGB(0, 0, 0, 0),
    enableDrag: true,
    barrierColor: const Color.fromARGB(118, 0, 0, 0),
    builder: (context) => AddRecordSheet(
      onAdded: onAdded,
      transaction: transaction,
    ),
  );
}
