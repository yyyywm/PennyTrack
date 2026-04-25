import 'package:flutter/material.dart';

/// 将后端图标名称映射为 MaterialIcons codePoint
///
/// 集中管理映射表，避免在 api_service.dart 和 add_record_sheet.dart 中重复定义。
int iconNameToCodePoint(String? iconName, bool isIncome) {
  final Map<String, IconData> iconMap = {
    'fa-money': Icons.attach_money,
    'fa-briefcase': Icons.work_outline,
    'fa-line-chart': Icons.trending_up,
    'fa-gift': Icons.card_giftcard,
    'fa-ellipsis-h': Icons.more_horiz,
    'fa-cutlery': Icons.restaurant,
    'fa-car': Icons.directions_car,
    'fa-shopping-bag': Icons.shopping_bag,
    'fa-home': Icons.home,
    'fa-film': Icons.movie,
    'fa-medkit': Icons.local_hospital,
    'fa-book': Icons.school,
  };

  if (iconName != null && iconMap.containsKey(iconName)) {
    return iconMap[iconName]!.codePoint;
  }

  return isIncome
      ? Icons.trending_up.codePoint
      : Icons.shopping_cart.codePoint;
}
