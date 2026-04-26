import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// 离线时使用的默认分类，与后端 `create_user` 中的种子数据保持一致。
  List<Category> _defaultCategories() {
    return [
      Category(id: -1, name: '工资', type: 'income', icon: 'fa-money', color: 'green'),
      Category(id: -2, name: '兼职', type: 'income', icon: 'fa-briefcase', color: 'teal'),
      Category(id: -3, name: '投资', type: 'income', icon: 'fa-line-chart', color: 'emerald'),
      Category(id: -4, name: '礼金', type: 'income', icon: 'fa-gift', color: 'lime'),
      Category(id: -5, name: '其他', type: 'income', icon: 'fa-ellipsis-h', color: 'cyan'),
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
    return Category(
        id: -13,
        name: '其他',
        type: 'expense',
        icon: 'fa-ellipsis-h',
        color: 'gray');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (_, controller) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 手柄
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 标题
                    Text(
                      _isEdit ? '编辑记录' : '添加新记录',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 收入/支出切换（顶部）
                    _buildTypeToggle(),
                    const SizedBox(height: 20),

                    // 金额（放大）
                    _buildAmountInput(),
                    const SizedBox(height: 20),

                    // 名称
                    _buildSectionLabel('名称 / 备注'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: '可不填，默认使用分类名',
                        prefixIcon: const Icon(Icons.edit_note),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 12),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 分类
                    _buildSectionLabel('分类'),
                    const SizedBox(height: 8),
                    _buildCategoryChips(),
                    const SizedBox(height: 18),

                    // 日期
                    _buildSectionLabel('日期'),
                    const SizedBox(height: 8),
                    _buildDateTile(),
                    const SizedBox(height: 24),

                    // 按钮组
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 46,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _submit,
                              child: Text(
                                _isEdit ? '保存' : '确定',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ========== 收支切换（置顶） ==========
  Widget _buildTypeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: _toggleSegment(label: '支出', isSelected: !_isIncome, color: Colors.red[700]!, onTap: () => _setType(false))),
          Expanded(child: _toggleSegment(label: '收入', isSelected: _isIncome, color: Colors.green[700]!, onTap: () => _setType(true))),
        ],
      ),
    );
  }

  Widget _toggleSegment({
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected ? color : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  void _setType(bool isIncome) {
    if (_isIncome == isIncome) return;
    setState(() {
      _isIncome = isIncome;
      _selectedCategory = null;
    });
  }

  // ========== 金额输入（放大） ==========
  Widget _buildAmountInput() {
    final color = _isIncome ? Colors.green[700]! : Colors.red[700]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '￥',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey[400],
                ),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========== 分类 Chips ==========
  Widget _buildCategoryChips() {
    if (_isLoadingCategories) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final visible = _categories
        .where((c) =>
            (_isIncome && c.type == 'income') ||
            (!_isIncome && c.type == 'expense'))
        .toList();

    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '暂无可用分类',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      );
    }

    final accent = _isIncome ? Colors.green[700]! : Colors.red[700]!;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: visible.map((c) {
        final selected = _selectedCategory?.id == c.id;
        return GestureDetector(
          onTap: () => setState(() => _selectedCategory = c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.13) : Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? accent : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  iconNameToIconData(c.icon, _isIncome),
                  size: 16,
                  color: selected ? accent : Colors.grey[700],
                ),
                const SizedBox(width: 6),
                Text(
                  c.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? accent : Colors.grey[800],
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ========== 日期 ==========
  Widget _buildDateTile() {
    final dateStr =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
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
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 18, color: Colors.grey[700]),
            const SizedBox(width: 10),
            Text(
              dateStr,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey[700],
        ),
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
    backgroundColor: Colors.transparent,
    enableDrag: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => AddRecordSheet(
      onAdded: onAdded,
      transaction: transaction,
    ),
  );
}
