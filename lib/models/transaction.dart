/// 记账交易记录数据模型
class Transaction {
  final String id;
  final String name;
  final String type;
  final double amount;
  final bool isIncome;
  final DateTime date;
  final int iconCodePoint;
  final int? categoryId;

  Transaction({
    required this.id,
    required this.name,
    required this.type,
    required this.amount,
    required this.isIncome,
    required this.date,
    required this.iconCodePoint,
    this.categoryId,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    double parseAmount() {
      if (json['amount'] != null) {
        final v = json['amount'];
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString()) ?? 0;
      }
      // 兼容旧数据格式 '18￥'
      final priceStr = json['price']?.toString() ?? '0';
      return double.tryParse(priceStr.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
    }

    int parseIcon() {
      final v = json['icon'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0xe332; // Icons.shopping_cart
    }

    int? parseCategoryId() {
      final v = json['categoryId'] ?? json['category_id'];
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    DateTime parseDate() {
      try {
        return DateTime.parse(json['date'].toString());
      } catch (_) {
        return DateTime.now();
      }
    }

    return Transaction(
      // 后端返回 int，本地存储为 String，统一用 toString 兼容两种来源
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      amount: parseAmount(),
      isIncome: json['isIncome'] == true,
      date: parseDate(),
      iconCodePoint: parseIcon(),
      categoryId: parseCategoryId(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'amount': amount,
      'isIncome': isIncome,
      'date': date.toIso8601String(),
      'icon': iconCodePoint,
      'categoryId': categoryId,
    };
  }

  /// 格式化后的金额显示，例如 "+18.00￥" 或 "-25.50￥"
  String get displayPrice {
    final prefix = isIncome ? '+' : '-';
    return '$prefix${amount.toStringAsFixed(2)}￥';
  }
}
