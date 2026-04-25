import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'statistics_page.dart';

/// 主导航页面：包含侧边栏和页面切换
class NavigatePage extends StatefulWidget {
  const NavigatePage({super.key});

  @override
  State<NavigatePage> createState() => _NavigatePageState();
}

class _NavigatePageState extends State<NavigatePage> {
  int _selectedIndex = 0;

  final _pages = const <Widget>[
    HomePage(),
    StatisticsPage(),
    LoginPage(),
  ];

  final _drawerItems = const <Map<String, dynamic>>[
    {'icon': Icons.home, 'title': '首页'},
    {'icon': Icons.analytics, 'title': '统计'},
    {'icon': Icons.people, 'title': '我的'},
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

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;

    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: _pages[_selectedIndex],
      ),
      drawer: Drawer(
        width: 240,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              CircleAvatar(
                backgroundImage: auth.isLoggedIn && auth.userProfile != null
                    ? const AssetImage('assets/images/me.png')
                    : null,
                radius: 50,
                child: auth.isLoggedIn && auth.userProfile != null
                    ? null
                    : const Icon(Icons.person, size: 40),
              ),
              const SizedBox(height: 12),
              Text(
                auth.isLoggedIn && auth.userProfile != null
                    ? auth.userProfile!.username
                    : '未登录',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (auth.isLoggedIn && auth.userProfile != null)
                Text(
                  auth.userProfile!.email,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: _drawerItems.length,
                  itemBuilder: (context, index) {
                    final item = _drawerItems[index];
                    return ListTile(
                      leading: Icon(item['icon'] as IconData),
                      title: Text(item['title'] as String),
                      selected: _selectedIndex == index,
                      onTap: () {
                        setState(() {
                          _selectedIndex = index;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
              if (auth.isLoggedIn)
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('退出登录',
                      style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    await auth.logout();
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('已登出')),
                    );
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
