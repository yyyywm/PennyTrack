import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/transaction.dart';

/// 本地存储服务：管理每日记账数据的持久化
///
/// 数据按天自动隔离，跨天时自动清空前一天数据。
class StorageService {
  static const String _keyMenuItems = 'menu_items_today';
  static const String _keyLastClearDate = 'last_clear_date';

  /// 加载今天的项目（首次加载当天数据时，若日期变化则清空旧数据）
  static Future<List<Transaction>> loadTodayItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _getTodayString();
      final lastClearDate = prefs.getString(_keyLastClearDate);

      if (lastClearDate != today) {
        await clearAllLocalItems();
        await prefs.setString(_keyLastClearDate, today);
      }

      final data = prefs.getString(_keyMenuItems);
      if (data == null || data.isEmpty) {
        return [];
      }

      final List<dynamic> decoded = jsonDecode(data);
      return decoded
          .cast<Map<String, dynamic>>()
          .map(Transaction.fromJson)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 添加一条记录
  static Future<void> addItem(Transaction item) async {
    final items = await loadTodayItems();
    items.add(item);
    await saveTodayItems(items);
  }

  /// 根据 ID 删除一条记录
  static Future<void> deleteItemById(String id) async {
    final items = await loadTodayItems();
    items.removeWhere((item) => item.id == id);
    await saveTodayItems(items);
  }

  /// 根据 ID 查询一条记录（返回 null 如果没找到）
  static Future<Transaction?> findItemById(String id) async {
    final items = await loadTodayItems();
    return items.firstWhereOrNull((item) => item.id == id);
  }

  /// 覆盖保存整个列表
  static Future<bool> saveTodayItems(List<Transaction> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(items.map((t) => t.toJson()).toList());
      return prefs.setString(_keyMenuItems, encoded);
    } catch (e) {
      return false;
    }
  }

  /// 手动清空今日数据
  static Future<void> clearTodayItems() async {
    await clearAllLocalItems();
    final prefs = await SharedPreferences.getInstance();
    final today = _getTodayString();
    await prefs.setString(_keyLastClearDate, today);
  }

  /// 清空所有本地缓存数据（不更新日期标记）
  ///
  /// 用于同步完成后清理本地离线记录，或手动重置。
  static Future<void> clearAllLocalItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyMenuItems);
  }

  /// 获取今天的日期字符串（格式：2025-09-21）
  static String _getTodayString() {
    return DateTime.now().toIso8601String().split('T')[0];
  }
}
