import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'statistics_page.dart';

/// 主导航页面：底部 NavigationBar + 中央悬浮 FAB（添加记录）
class NavigatePage extends StatefulWidget {
  const NavigatePage({super.key});

  @override
  State<NavigatePage> createState() => _NavigatePageState();
}

class _NavigatePageState extends State<NavigatePage> {
  int _selectedIndex = 0;
  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();

  late final List<Widget> _pages = [
    HomePage(key: _homeKey),
    const StatisticsPage(),
    const LoginPage(),
  ];

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  void _onAddPressed() {
    // 切换到首页并通过 GlobalKey 触发首页内的添加弹窗，
    // 复用首页已有的登录态判断、API/本地分发与列表刷新逻辑。
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
    }
    // 等当前帧渲染完再调用，确保 HomePage 已经 build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _homeKey.currentState?.openAddSheet();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onAddPressed,
        elevation: 2,
        highlightElevation: 4,
        shape: const CircleBorder(),
        tooltip: '添加记录',
        child: const Icon(Icons.add, size: 30),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        height: 60,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
            tooltip: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: '统计',
            tooltip: '统计',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
            tooltip: '我的',
          ),
        ],
      ),
    );
  }
}
