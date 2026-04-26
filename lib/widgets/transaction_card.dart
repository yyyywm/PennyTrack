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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: transaction.isIncome ? Colors.green[50] : Colors.red[50],
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showEditSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                codePointToIconData(transaction.iconCodePoint, transaction.isIncome),
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '${transaction.date.year}-${transaction.date.month.toString().padLeft(2, '0')}-${transaction.date.day.toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Text(
                transaction.displayPrice,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
        ),
      ),
    );
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
