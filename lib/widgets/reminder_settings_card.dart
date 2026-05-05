import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../utils/toast_utils.dart';

/// 每日记账提醒设置卡片
///
/// 提供：
///   * 总开关
///   * 多个时间点（增/删）
///   * 测试通知
///   * 国产 ROM 兼容入口（电池优化白名单 / 自启动 / 通知设置）
class ReminderSettingsCard extends StatefulWidget {
  const ReminderSettingsCard({super.key});

  @override
  State<ReminderSettingsCard> createState() => _ReminderSettingsCardState();
}

class _ReminderSettingsCardState extends State<ReminderSettingsCard> {
  bool _enabled = false;
  List<String> _times = [];
  bool _loading = true;
  bool _showOemTips = false;
  bool _devMode = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await StorageService.isReminderEnabled();
    final times = await StorageService.loadReminderTimes();
    final oem = await NotificationService.instance.isChineseOemRom();
    final devMode = await StorageService.isDevModeEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _times = times;
      _showOemTips = oem;
      _devMode = devMode;
      _loading = false;
    });
  }

  Future<void> _onToggle(bool value) async {
    if (value) {
      // 打开前先申请权限
      final ok = await NotificationService.instance.requestAllPermissions();
      if (!ok) {
        if (!mounted) return;
        showCenterToast(
          context: context,
          message: '需要通知权限才能开启提醒',
          icon: Icons.error_outline,
          backgroundColor: Colors.orange,
        );
        return;
      }
      // 默认给一个 21:00（用户没设过任何时间的话）
      final times = _times.isEmpty ? <String>['21:00'] : _times;
      // 先更新 UI，避免后台调度耗时让 Switch 看起来「点不动」
      setState(() {
        _enabled = true;
        _times = times;
      });

      ReminderDiagnostics? diag;
      String? errorMsg;
      try {
        diag = await NotificationService.instance.enableAndSchedule(times);
      } catch (e) {
        errorMsg = e.toString();
      }

      if (!mounted) return;
      showCenterToast(
        context: context,
        message: '提醒已开启',
        icon: Icons.notifications_active,
        backgroundColor: Colors.green,
      );

      // 用 toast 显示诊断信息（比弹窗更可靠，国产 ROM 可能拦截弹窗）
      final info = diag?.toString() ?? '诊断: $errorMsg';
      _showLongToast(info);
    } else {
      setState(() => _enabled = false);
      try {
        await NotificationService.instance.disable();
      } catch (e) {
        debugPrint('Disable reminder failed: $e');
      }
      if (!mounted) return;
      showCenterToast(
        context: context,
        message: '提醒已关闭',
        icon: Icons.notifications_off_outlined,
      );
    }
  }

  void _showLongToast(String message) {
    if (!mounted) return;
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      SnackBar(
        content: SelectableText(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '关闭',
          onPressed: () => scaffold.hideCurrentSnackBar(),
        ),
      ),
    );
  }

  Future<void> _showDiagnostics() async {
    if (!mounted) return;
    showCenterToast(
      context: context,
      message: '正在检查...',
      icon: Icons.hourglass_top,
    );
    final diag = await NotificationService.instance.getDiagnostics();
    if (!mounted) return;
    _showLongToast(diag.toString());
  }

  void _showDiagnosticsDialog(ReminderDiagnostics diag) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提醒诊断信息'),
        content: SingleChildScrollView(
          child: SelectableText(diag.toString()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: SelectableText(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _onDevModeToggle(bool value) async {
    setState(() => _devMode = value);
    await StorageService.setDevModeEnabled(value);
    if (!mounted) return;
    showCenterToast(
      context: context,
      message: value ? '开发者模式已开启' : '开发者模式已关闭',
      icon: value ? Icons.build_circle_outlined : Icons.build_outlined,
      backgroundColor: value ? Colors.orange : Colors.grey,
    );
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 21, minute: 0),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final hhmm = _formatTime(picked);
    if (_times.contains(hhmm)) {
      if (!mounted) return;
      showCenterToast(
        context: context,
        message: '该时间已存在',
        icon: Icons.info_outline,
        backgroundColor: Colors.orange,
      );
      return;
    }
    final next = [..._times, hhmm]..sort();
    // 先更新 UI，再做异步调度，避免后台调度抛异常时 chip 不刷新
    if (!mounted) return;
    setState(() => _times = next);
    try {
      if (_enabled) {
        await NotificationService.instance.enableAndSchedule(next);
      } else {
        await StorageService.saveReminderTimes(next);
      }
    } catch (e) {
      debugPrint('Add reminder time failed: $e');
    }
  }

  Future<void> _removeTime(String hhmm) async {
    final next = _times.where((e) => e != hhmm).toList();
    // 先更新 UI，再做异步调度
    if (!mounted) return;
    setState(() {
      _times = next;
      if (_enabled && next.isEmpty) _enabled = false;
    });
    try {
      if (next.isEmpty) {
        // 全部删除则关闭
        await NotificationService.instance.disable();
      } else if (_enabled) {
        await NotificationService.instance.enableAndSchedule(next);
      } else {
        await StorageService.saveReminderTimes(next);
      }
    } catch (e) {
      debugPrint('Remove reminder time failed: $e');
    }
  }

  Future<void> _editTime(String oldTime) async {
    final parts = oldTime.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final hhmm = _formatTime(picked);
    if (hhmm == oldTime) return;
    if (_times.contains(hhmm)) {
      if (!mounted) return;
      showCenterToast(
        context: context,
        message: '该时间已存在',
        icon: Icons.info_outline,
        backgroundColor: Colors.orange,
      );
      return;
    }
    final next = _times.map((e) => e == oldTime ? hhmm : e).toList()..sort();
    // 先更新 UI，再做异步调度。避免 enableAndSchedule 在国产 ROM 上
    // 抛未捕获异常时，chip 文本卡在旧时间（典型现象：选完仍显示 21:00）
    if (!mounted) return;
    setState(() => _times = next);
    try {
      if (_enabled) {
        await NotificationService.instance.enableAndSchedule(next);
      } else {
        await StorageService.saveReminderTimes(next);
      }
    } catch (e) {
      debugPrint('Edit reminder time failed: $e');
    }
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _sendTest() async {
    final ok = await NotificationService.instance.requestAllPermissions();
    if (!ok) {
      if (!mounted) return;
      showCenterToast(
        context: context,
        message: '请先授予通知权限',
        icon: Icons.error_outline,
        backgroundColor: Colors.orange,
      );
      return;
    }
    await NotificationService.instance.showTestNotification();
    if (!mounted) return;
    showCenterToast(
      context: context,
      message: '测试通知已发送',
      icon: Icons.send,
      backgroundColor: Colors.green,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // 主开关
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (_enabled ? Colors.green : Colors.grey).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _enabled
                    ? Icons.notifications_active
                    : Icons.notifications_none,
                color: _enabled ? Colors.green[700] : Colors.grey[700],
              ),
            ),
            title: const Text(
              '每日记账提醒',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _enabled
                  ? '已启用，将在指定时间发送通知'
                  : '关闭中，开启后无需登录也能收到提醒',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Switch(
              value: _enabled,
              onChanged: _onToggle,
            ),
          ),

          if (_enabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            // 时间点列表
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    '提醒时间',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addTime,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加'),
                    style: TextButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),

            if (_times.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(
                  '尚未添加提醒时间，点右上角「添加」',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _times.map(_buildTimeChip).toList(),
                ),
              ),
          ],

          if (_enabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              dense: true,
              leading: const Icon(Icons.send_outlined),
              title: const Text('发送一条测试通知'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _sendTest,
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('查看诊断信息'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showDiagnostics,
            ),
          ],

          if (_enabled && _showOemTips) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined,
                      size: 16, color: Colors.amber[800]),
                  const SizedBox(width: 6),
                  Text(
                    '国产 ROM 提醒可能被系统拦截',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber[900],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '若到时间没收到通知，请把本应用加入「自启动 / 后台运行 / 电池优化」白名单。',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _oemActionButton(
                    icon: Icons.battery_charging_full,
                    label: '电池优化',
                    onTap: NotificationService
                        .instance.openBatteryOptimizationSettings,
                  ),
                  _oemActionButton(
                    icon: Icons.power_settings_new,
                    label: '自启动管理',
                    onTap: NotificationService
                        .instance.openOemAutoStartSettings,
                  ),
                  _oemActionButton(
                    icon: Icons.notifications_outlined,
                    label: '通知设置',
                    onTap: NotificationService
                        .instance.openAppNotificationSettings,
                  ),
                ],
              ),
            ),
          ],

          // 开发者模式开关
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            leading: Icon(
              Icons.build_outlined,
              size: 20,
              color: _devMode ? Colors.orange : Colors.grey,
            ),
            title: const Text(
              '开发者模式',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              '开启后设置提醒会弹出诊断信息',
              style: TextStyle(fontSize: 11),
            ),
            trailing: Switch(
              value: _devMode,
              onChanged: _onDevModeToggle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeChip(String hhmm) {
    return GestureDetector(
      onTap: () => _editTime(hhmm),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time, size: 14, color: Colors.blue[800]),
            const SizedBox(width: 4),
            Text(
              hhmm,
              style: TextStyle(
                fontSize: 13,
                color: Colors.blue[900],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => _removeTime(hhmm),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child:
                    Icon(Icons.close, size: 14, color: Colors.blue[700]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _oemActionButton({
    required IconData icon,
    required String label,
    required Future<void> Function() onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
