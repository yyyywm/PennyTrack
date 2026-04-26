import 'dart:async';

import '../models/transaction.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// 本地→后端数据同步服务
///
/// 使用场景：
/// - 用户离线创建了若干本地记录（id 为本地时间戳字符串）。
/// - 登录成功后调用 [syncLocalToBackend] 将这些记录批量上传到后端，
///   全部成功后清空本地缓存，避免与后端 int 主键 ID 体系并存。
class SyncResult {
  final int total;
  final int success;
  final int failed;

  SyncResult({required this.total, required this.success, required this.failed});

  bool get hasLocal => total > 0;
  bool get allSucceeded => total == success;
}

class SyncService {
  static Completer<SyncResult>? _syncCompleter;

  /// 把本地未同步的交易上传到后端。仅在已登录时执行。
  ///
  /// 返回同步结果统计。如果全部成功，本地缓存会被清空。
  ///
  /// 本方法带有互斥锁保护：同一时刻只允许一个同步任务在执行，
  /// 后续并发调用会等待当前同步完成后返回相同的结果，避免重复上传。
  static Future<SyncResult> syncLocalToBackend() async {
    if (_syncCompleter != null) {
      return _syncCompleter!.future;
    }

    _syncCompleter = Completer<SyncResult>();
    try {
      final result = await _doSync();
      _syncCompleter!.complete(result);
      return result;
    } catch (e, st) {
      _syncCompleter!.completeError(e, st);
      rethrow;
    } finally {
      _syncCompleter = null;
    }
  }

  static Future<SyncResult> _doSync() async {
    final localItems = await StorageService.loadTodayItems();
    if (localItems.isEmpty) {
      return SyncResult(total: 0, success: 0, failed: 0);
    }

    int success = 0;
    final List<Transaction> failedItems = [];

    for (final item in localItems) {
      try {
        final created = await ApiService.createTransaction(item);
        if (created != null) {
          success++;
        } else {
          failedItems.add(item);
        }
      } catch (_) {
        failedItems.add(item);
      }
    }

    // 全部成功才清空本地，否则保留失败项以便下次重试
    if (failedItems.isEmpty) {
      await StorageService.clearAllLocalItems();
    } else {
      await StorageService.saveTodayItems(failedItems);
    }

    return SyncResult(
      total: localItems.length,
      success: success,
      failed: failedItems.length,
    );
  }
}
