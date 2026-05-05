import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import 'dart:convert';

import '../models/transaction.dart';

/// 本地存储服务：管理每日记账数据的持久化
///
/// 数据按天自动隔离，跨天时自动清空前一天数据。
class StorageService {
  static const String _keyMenuItems = 'menu_items_today';
  static const String _keyLastClearDate = 'last_clear_date';

  /// 提醒功能：开关
  static const String _keyReminderEnabled = 'reminder_enabled';

  /// 提醒功能：时间点列表（格式 "HH:MM"，例如 ["09:00", "21:30"]）
  static const String _keyReminderTimes = 'reminder_times';

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

  // ========== 每日提醒配置 ==========

  /// 提醒总开关是否开启（默认 false）
  static Future<bool> isReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyReminderEnabled) ?? false;
  }

  /// 设置提醒总开关
  static Future<void> setReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReminderEnabled, enabled);
  }

  /// 加载所有提醒时间点（按 "HH:MM" 字典序升序）
  static Future<List<String>> loadReminderTimes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyReminderTimes) ?? const <String>[];
    final valid = raw.where(_isValidTimeString).toSet().toList();
    valid.sort();
    return valid;
  }

  /// 保存提醒时间点列表（自动去重 + 校验 + 排序）
  static Future<void> saveReminderTimes(List<String> times) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = times.where(_isValidTimeString).toSet().toList()..sort();
    await prefs.setStringList(_keyReminderTimes, cleaned);
  }

  /// 校验 "HH:MM" 字符串是否合法
  static bool _isValidTimeString(String s) {
    final m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(s);
    return m != null;
  }

  // ========== 开发者模式配置 ==========

  static const String _keyDevModeEnabled = 'dev_mode_enabled';

  /// 开发者模式是否开启（默认 false）
  static Future<bool> isDevModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDevModeEnabled) ?? false;
  }

  /// 设置开发者模式开关
  static Future<void> setDevModeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDevModeEnabled, enabled);
  }
}
