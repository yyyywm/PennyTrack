import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'storage_service.dart';

/// 通知点击回调：通过 [payload] 携带跳转信息（这里固定为 "open_add"）。
typedef NotificationTapHandler = void Function(String? payload);

/// 每日记账提醒服务（单例）
///
/// 设计要点：
///   * 与登录态完全解耦——本地调度，未登录也能用
///   * 调度方式使用 [AndroidScheduleMode.exactAllowWhileIdle]，
///     底层走 AlarmManager，应用无需常驻后台
///   * 多个时间点：每个时间点 id = hour*100 + minute，便于增量更新
///   * ColorOS / OPPO / OnePlus 等国产 ROM 兼容：
///       - app 启动时无条件重新注册一次，规避被「锁屏清理」杀掉的定时任务
///       - 提供「打开自启动管理 / 电池优化白名单」深链
///   * 通知点击后通过 [tapHandler] 回到 UI 层处理（弹出 AddRecordSheet）
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'daily_reminder_channel';
  static const String _channelName = '每日记账提醒';
  static const String _channelDesc = '在你设置的时间发送通知，提醒你打开 App 记一笔';
  static const String _payload = 'open_add';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// 由 UI 层注册的通知点击回调（点击通知后跳转添加记录）
  NotificationTapHandler? _tapHandler;

  /// 冷启动时携带的待处理 payload（应用未运行时点击通知导致的启动）
  String? _pendingLaunchPayload;

  /// UI 层在 navigatorKey 准备好后注册通知点击回调
  void registerTapHandler(NotificationTapHandler handler) {
    _tapHandler = handler;
    // 若有冷启动 payload，注册完立刻消费一次
    if (_pendingLaunchPayload != null) {
      final p = _pendingLaunchPayload!;
      _pendingLaunchPayload = null;
      handler(p);
    }
  }

  /// 应用启动时调用：初始化插件 + 时区 + 检查冷启动 payload + 重新调度提醒
  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    _setupLocalTimezone();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // 处理冷启动场景（应用被杀后用户点击通知导致启动）
    // 部分设备上 getNotificationAppLaunchDetails 可能死锁，加超时保护
    try {
      final launchDetails = await _plugin
          .getNotificationAppLaunchDetails()
          .timeout(const Duration(seconds: 2));
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _pendingLaunchPayload = launchDetails?.notificationResponse?.payload;
      }
    } catch (_) {
      // 超时或异常，忽略冷启动 payload
    }

    // 创建通知渠道（Android 8+ 必需）
    await _ensureChannel();

    _initialized = true;

    // 延迟重新调度提醒，避免阻塞应用启动
    Future.microtask(() => rescheduleFromStorage());
  }

  /// 为 timezone 包设置本地时区。
  ///
  /// 兼容性挑战：
  ///   * 中文系统：`DateTime.now().timeZoneName` 返回「中国标准时间」（无法映射）
  ///   * 部分英文系统返回缩写 "CST"（不是 IANA 名称）
  ///   * 极少设备直接返回 "Asia/Shanghai"
  ///
  /// 策略：先尝试名称映射 → 名称失败时按 UTC 偏移量挑一个 IANA 区。
  /// 若 tz.local 与设备实际偏移不一致，`zonedSchedule` 会把闹钟错算到错误时间
  /// （例如一加 15 上 21:00 反而在凌晨 5:00 触发），所以这一步必须可靠。
  void _setupLocalTimezone() {
    // 1. 优先按名称映射
    final name = DateTime.now().timeZoneName;
    final mapped = _knownTimeZoneNames[name] ?? name;
    try {
      tz.setLocalLocation(tz.getLocation(mapped));
      return;
    } catch (_) {
      // 落入第 2 步
    }

    // 2. 按 UTC 偏移量回落到具有相同偏移的 IANA 区
    final offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    final ianaByOffset = _ianaByUtcOffsetMinutes[offsetMinutes];
    if (ianaByOffset != null) {
      try {
        tz.setLocalLocation(tz.getLocation(ianaByOffset));
        return;
      } catch (_) {
        // 落入第 3 步
      }
    }

    // 3. 最终兜底：UTC（zonedSchedule 仍可工作，但用户看到的提醒时间会差几个小时）
    tz.setLocalLocation(tz.UTC);
  }

  /// 设备返回的非 IANA 名称 → IANA 时区映射
  static const Map<String, String> _knownTimeZoneNames = {
    'CST': 'Asia/Shanghai', // 中国标准时间（也是美国中部时间，这里按中国市场偏好）
    '中国标准时间': 'Asia/Shanghai',
    'China Standard Time': 'Asia/Shanghai',
    'JST': 'Asia/Tokyo',
    '日本标准时间': 'Asia/Tokyo',
    'KST': 'Asia/Seoul',
    'IST': 'Asia/Kolkata',
    'GMT': 'UTC',
    'UTC': 'UTC',
    'BST': 'Europe/London',
    'CET': 'Europe/Berlin',
    'EET': 'Europe/Helsinki',
    'PST': 'America/Los_Angeles',
    'PDT': 'America/Los_Angeles',
    'MST': 'America/Denver',
    'MDT': 'America/Denver',
    'EST': 'America/New_York',
    'EDT': 'America/New_York',
  };

  /// 按 UTC 偏移量（分钟）挑选一个代表性的 IANA 区
  static const Map<int, String> _ianaByUtcOffsetMinutes = {
    -480: 'America/Los_Angeles', // -8:00
    -300: 'America/New_York', //    -5:00
    0: 'UTC', //                     0:00
    60: 'Europe/Berlin', //          1:00
    180: 'Europe/Moscow', //         3:00
    330: 'Asia/Kolkata', //          5:30
    420: 'Asia/Bangkok', //          7:00
    480: 'Asia/Shanghai', //         8:00
    540: 'Asia/Tokyo', //            9:00
    600: 'Australia/Sydney', //      10:00
  };

  Future<void> _ensureChannel() async {
    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
      playSound: false,
      enableVibration: true,
    );
    await android.createNotificationChannel(channel);
  }

  void _onNotificationResponse(NotificationResponse response) {
    final handler = _tapHandler;
    if (handler != null) {
      handler(response.payload);
    } else {
      _pendingLaunchPayload = response.payload;
    }
  }

  // ========== 权限 ==========

  /// 请求所有提醒所需权限。返回 false 表示用户拒绝了关键权限。
  Future<bool> requestAllPermissions() async {
    if (!Platform.isAndroid) return true;

    // 1. POST_NOTIFICATIONS（Android 13+）
    final notif = await Permission.notification.request();
    if (!notif.isGranted) return false;

    // 2. SCHEDULE_EXACT_ALARM（Android 12+，部分国产 ROM 不要求）
    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      try {
        final canExact = await android.canScheduleExactNotifications();
        if (canExact == false) {
          await android.requestExactAlarmsPermission();
        }
      } catch (_) {
        // 老版本插件没有该方法，忽略
      }
    }

    return true;
  }

  /// 当前系统是否允许发送通知
  Future<bool> hasNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    return Permission.notification.isGranted;
  }

  // ========== 调度 ==========

  /// 启用提醒并按 [times] 重新注册全部时间点
  Future<void> enableAndSchedule(List<String> times) async {
    await StorageService.setReminderEnabled(true);
    await StorageService.saveReminderTimes(times);
    await _rescheduleAll(times);
  }

  /// 关闭提醒并取消所有已注册通知
  Future<void> disable() async {
    await StorageService.setReminderEnabled(false);
    await _plugin.cancelAll();
  }

  /// 根据本地存储的开关 + 时间列表恢复定时（应用启动 / 设备重启后）
  Future<void> rescheduleFromStorage() async {
    final enabled = await StorageService.isReminderEnabled();
    if (!enabled) {
      await _plugin.cancelAll();
      return;
    }
    final times = await StorageService.loadReminderTimes();
    await _rescheduleAll(times);
  }

  /// 读取已挂起的通知（调试用）
  Future<List<PendingNotificationRequest>> pendingNotifications() {
    return _plugin.pendingNotificationRequests();
  }

  /// 立刻发一条用于自检的通知
  Future<void> showTestNotification() async {
    await _plugin.show(
      999999,
      '记账提醒已开启',
      '稍后到设置的时间会再次提醒你',
      _buildDetails(),
      payload: _payload,
    );
  }

  Future<void> _rescheduleAll(List<String> times) async {
    await _plugin.cancelAll();
    for (final t in times) {
      await _scheduleOne(t);
    }
  }

  Future<void> _scheduleOne(String hhmm) async {
    final parts = hhmm.split(':');
    if (parts.length != 2) return;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return;

    final id = h * 100 + m;
    final scheduledAt = _nextInstanceOf(h, m);

    try {
      await _plugin.zonedSchedule(
        id,
        '该记账啦 💰',
        '别忘了把今天的支出 / 收入记一下，几秒就能搞定～',
        scheduledAt,
        _buildDetails(),
        // ColorOS 16 / 一加 15 (OxygenOS) 测试可用：exactAllowWhileIdle
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // 每天同一时间
        payload: _payload,
      );
    } catch (e) {
      // 部分设备无 SCHEDULE_EXACT_ALARM 权限时，回落到 inexact
      if (kDebugMode) {
        debugPrint('Exact schedule failed for $hhmm: $e -> fallback inexact');
      }
      try {
        await _plugin.zonedSchedule(
          id,
          '该记账啦 💰',
          '别忘了把今天的支出 / 收入记一下，几秒就能搞定～',
          scheduledAt,
          _buildDetails(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: _payload,
        );
      } catch (e2) {
        // 国产 ROM 上 inexact 也可能失败；这里吞掉避免冒泡到 UI
        // 否则上层 setState 永远不会执行（典型表现：编辑时间后 UI 不刷新）
        if (kDebugMode) {
          debugPrint('Inexact schedule also failed for $hhmm: $e2');
        }
      }
    }
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  NotificationDetails _buildDetails() {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: false,
      enableVibration: true,
      ticker: '记账提醒',
      category: AndroidNotificationCategory.reminder,
    );
    return const NotificationDetails(android: androidDetails);
  }

  // ========== 国产 ROM 深度兼容入口 ==========

  /// 当前是否运行在国产 OEM ROM 上（OPPO / OnePlus / realme / Xiaomi / Huawei 等）
  Future<bool> isChineseOemRom() async {
    if (!Platform.isAndroid) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final m = info.manufacturer.toLowerCase();
      return m.contains('oppo') ||
          m.contains('oneplus') ||
          m.contains('realme') ||
          m.contains('xiaomi') ||
          m.contains('redmi') ||
          m.contains('huawei') ||
          m.contains('honor') ||
          m.contains('vivo');
    } catch (_) {
      return false;
    }
  }

  static const String _packageName = 'com.pennytrack.app';

  /// 打开应用通知设置页（所有 Android 通用）
  Future<void> openAppNotificationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      const intent = AndroidIntent(
        action: 'android.settings.APP_NOTIFICATION_SETTINGS',
        arguments: <String, dynamic>{
          'android.provider.extra.APP_PACKAGE': _packageName,
        },
      );
      await intent.launch();
    } catch (_) {
      await openAppDetailsSettings();
    }
  }

  /// 打开应用详情页（兜底，所有 Android 通用）
  Future<void> openAppDetailsSettings() async {
    if (!Platform.isAndroid) return;
    try {
      const intent = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$_packageName',
      );
      await intent.launch();
    } catch (_) {
      // ignore
    }
  }

  /// 打开「忽略电池优化」请求（OPPO / OnePlus / 一加 15 ColorOS 16 必备）
  Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      const intent = AndroidIntent(
        action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
      );
      await intent.launch();
    } catch (_) {
      await openAppDetailsSettings();
    }
  }

  /// 尝试打开 ColorOS / OPPO 自启动管理（不保证成功，失败回落到详情页）
  Future<void> openOemAutoStartSettings() async {
    if (!Platform.isAndroid) return;
    final candidates = <Map<String, String>>[
      // OPPO / OnePlus / realme ColorOS（部分版本）
      {
        'package': 'com.coloros.safecenter',
        'class':
            'com.coloros.safecenter.permission.startup.StartupAppListActivity'
      },
      {
        'package': 'com.coloros.safecenter',
        'class':
            'com.coloros.safecenter.startupapp.StartupAppListActivity'
      },
      // OPlus（ColorOS 13+ / 一加 15 测试版）
      {
        'package': 'com.oplus.safecenter',
        'class':
            'com.oplus.safecenter.permission.startup.StartupAppListActivity'
      },
      // OPPO 较老版本
      {
        'package': 'com.oppo.safe',
        'class': 'com.oppo.safe.permission.startup.StartupAppListActivity'
      },
      // Xiaomi
      {
        'package': 'com.miui.securitycenter',
        'class': 'com.miui.permcenter.autostart.AutoStartManagementActivity'
      },
      // Huawei
      {
        'package': 'com.huawei.systemmanager',
        'class':
            'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity'
      },
      // Vivo
      {
        'package': 'com.iqoo.secure',
        'class': 'com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity'
      },
    ];

    for (final c in candidates) {
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: c['package'],
          componentName: '${c['package']}/${c['class']}',
          flags: const <int>[0x10000000], // FLAG_ACTIVITY_NEW_TASK
        );
        await intent.launch();
        return;
      } catch (_) {
        // 尝试下一个
      }
    }
    // 全部失败，回落到应用详情页（用户可手动找到自启动选项）
    await openAppDetailsSettings();
  }
}
