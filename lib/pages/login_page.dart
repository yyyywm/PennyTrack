import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/reminder_settings_card.dart';
import 'register_page.dart';

/// 登录页面
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入用户名和密码')),
      );
      return;
    }

    final auth = AuthService.instance;
    final success = await auth.login(username, password);

    if (!mounted) return;

    if (success) {
      String message = '登录成功';
      final sync = auth.lastSyncResult;
      if (sync != null && sync.hasLocal) {
        if (sync.allSucceeded) {
          message += '，已同步本地 ${sync.success} 条记录';
        } else {
          message += '，本地 ${sync.success}/${sync.total} 条同步成功，'
              '${sync.failed} 条待重试';
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      _usernameController.clear();
      _passwordController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录失败，请检查用户名和密码')),
      );
    }
  }

  void _goToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;

    if (auth.isLoggedIn && auth.userProfile != null) {
      return _buildProfileView(auth);
    }

    return _buildLoginForm(auth);
  }

  // ========== 顶部 header（带柔和底色 + 居中） ==========
  Widget _buildHeader({
    required String title,
    required String subtitle,
    required double avatarRadius,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 28),
      decoration: BoxDecoration(
        // 柔和淡色底，与下方白色区块形成层次
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: avatarRadius,
              backgroundColor: Colors.white,
              backgroundImage: const AssetImage('assets/images/me.png'),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.black.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ========== 分区标题 ==========
  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ========== 卡片容器（与 ReminderSettingsCard 视觉一致） ==========
  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }

  // ========== 登录表单 ==========
  Widget _buildLoginForm(AuthService auth) {
    return SingleChildScrollView(
      // 底部预留导航栏 + 手势条空间，避免内容被 BottomNavigationBar 遮挡
      padding: EdgeInsets.only(
        bottom: 32 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        children: [
          _buildHeader(
            title: 'PennyTrack',
            subtitle: '记账，从一笔开始',
            avatarRadius: 42,
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle('登录账号'),
                _card(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: Colors.grey.shade200),
                          ),
                          hintText: '用户名',
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        textInputAction: TextInputAction.next,
                        enabled: !auth.isLoading,
                        autofillHints: const [AutofillHints.username],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: Colors.grey.shade200),
                          ),
                          hintText: '密码',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(
                                  () => _obscurePassword = !_obscurePassword);
                            },
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _handleLogin(),
                        enabled: !auth.isLoading,
                        autofillHints: const [AutofillHints.password],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: auth.isLoading ? null : _handleLogin,
                          child: auth.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text(
                                  '登录',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: TextButton(
                          onPressed: _goToRegister,
                          child: const Text('还没有账号？立即注册'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle('应用设置'),
                // 提醒设置（与登录态无关，未登录也可使用）
                const ReminderSettingsCard(),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ========== 个人资料视图 ==========
  Widget _buildProfileView(AuthService auth) {
    final profile = auth.userProfile!;
    return SingleChildScrollView(
      // 底部预留导航栏 + 手势条空间，避免内容被 BottomNavigationBar 遮挡
      padding: EdgeInsets.only(
        bottom: 32 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        children: [
          _buildHeader(
            title: profile.username,
            subtitle: profile.email,
            avatarRadius: 46,
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle('账户信息'),
                _card(
                  child: Column(
                    children: [
                      _buildInfoRow(
                        icon: Icons.alternate_email_outlined,
                        iconColor: Colors.blue,
                        label: '邮箱',
                        value: profile.email,
                      ),
                      Divider(
                        height: 1,
                        indent: 56,
                        endIndent: 16,
                        color: Colors.grey.shade200,
                      ),
                      _buildInfoRow(
                        icon: Icons.verified_user_outlined,
                        iconColor: Colors.green,
                        label: '账号状态',
                        value: '已登录',
                        valueChip: true,
                      ),
                      Divider(
                        height: 1,
                        indent: 56,
                        endIndent: 16,
                        color: Colors.grey.shade200,
                      ),
                      _buildInfoRow(
                        icon: Icons.person_outline,
                        iconColor: Colors.purple,
                        label: '用户名',
                        value: profile.username,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle('应用设置'),
                const ReminderSettingsCard(),
                const SizedBox(height: 28),
                // 退出登录按钮：填充式浅红，醒目但不刺眼
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.red.shade100),
                      ),
                    ),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text(
                      '退出登录',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5),
                    ),
                    onPressed: () async {
                      await auth.logout();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已登出')),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    bool valueChip = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          const Spacer(),
          Flexible(
            child: valueChip
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.green[700],
                      ),
                    ),
                  )
                : Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
          ),
        ],
      ),
    );
  }
}
