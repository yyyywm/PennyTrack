import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/navigate_page.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';

/// 全局 NavigatorKey，供通知点击回调跨上下文跳转使用
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 等待认证状态从本地存储恢复完成，避免启动时渲染未登录状态
  await AuthService.instance.initialize();

  // 初始化每日记账提醒（与登录态无关，离线也能用）
  // 此处会自动恢复已注册的提醒，并处理通知冷启动
  // 不 await，避免某些设备上插件初始化卡住导致无法进入首页
  unawaited(NotificationService.instance.initialize());

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PennyTrack',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 227, 234, 182),
        ),
      ),
      home: const NavigatePage(),
    );
  }
}
