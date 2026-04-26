import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../utils/icon_utils.dart';
import 'add_record_sheet.dart';

/// 单条交易记录的卡片组件
class TransactionCard extends StatelessWidget {
  final Transaction transaction;
  final Function(Transaction updated) onEdit;
  final Future<void> Function() onDeleteApi;

  const TransactionCard({
    super.key,
    required this.transaction,
    required this.onEdit,
    required this.onDeleteApi,
  });

  @override
  Widget build(BuildContext context) {
    final accent = transaction.isIncome ? Colors.green[700]! : Colors.red[700]!;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showEditSheet(context),
        onLongPress: () => _showActionSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              // 左侧分类色图标块
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  codePointToIconData(
                      transaction.iconCodePoint, transaction.isIncome),
                  size: 22,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              // 中间：名称 + 日期/类型
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _buildSubtitle(),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 右侧：金额
              Text(
                transaction.displayPrice,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildSubtitle() {
    final d = transaction.date;
    final dateStr = '${d.year}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    if (transaction.type.isNotEmpty && transaction.type != transaction.name) {
      return '${transaction.type} · $dateStr';
    }
    return dateStr;
  }

  void _showEditSheet(BuildContext context) {
    showAddRecordBottomSheet(
      context: context,
      transaction: transaction,
      onAdded: (updated) {
        onEdit(updated);
      },
    );
  }

  /// 长按弹出操作菜单（编辑 / 删除）
  void _showActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                transaction.name,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showEditSheet(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red[700]),
              title: Text('删除', style: TextStyle(color: Colors.red[700])),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确定要删除「${transaction.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await onDeleteApi();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
