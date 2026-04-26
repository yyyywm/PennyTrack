import 'package:flutter/material.dart';

const Map<String, IconData> _iconMap = {
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

const List<IconData> _allIcons = [
  Icons.attach_money,
  Icons.work_outline,
  Icons.trending_up,
  Icons.card_giftcard,
  Icons.more_horiz,
  Icons.restaurant,
  Icons.directions_car,
  Icons.shopping_bag,
  Icons.home,
  Icons.movie,
  Icons.local_hospital,
  Icons.school,
  Icons.shopping_cart,
];

/// 将后端图标名称映射为 MaterialIcons codePoint
///
/// 集中管理映射表，避免在 api_service.dart 和 add_record_sheet.dart 中重复定义。
int iconNameToCodePoint(String? iconName, bool isIncome) {
  return iconNameToIconData(iconName, isIncome).codePoint;
}

/// 将后端图标名称映射为 MaterialIcons 的 IconData 常量。
IconData iconNameToIconData(String? iconName, bool isIncome) {
  if (iconName != null && _iconMap.containsKey(iconName)) {
    return _iconMap[iconName]!;
  }
  return isIncome ? Icons.trending_up : Icons.shopping_cart;
}

/// 将 codePoint 映射回 MaterialIcons 的 IconData 常量。
IconData codePointToIconData(int codePoint, bool isIncome) {
  for (final icon in _allIcons) {
    if (icon.codePoint == codePoint) {
      return icon;
    }
  }
  return isIncome ? Icons.trending_up : Icons.shopping_cart;
}
