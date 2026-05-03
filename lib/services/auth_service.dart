import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'storage_service.dart';
import 'sync_service.dart';

/// 全局认证状态管理（单例）
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  static AuthService get instance => _instance;

  AuthService._internal() {
    // 注册 401 回调：token 被后端拒绝时自动登出
    ApiService.onUnauthorized = () {
      if (_token != null) logout();
    };
  }

  /// 初始化：从本地存储加载 token，应在 runApp 之前 await
  Future<void> initialize() async {
    try {
      await _loadTokenFromStorage();
    } catch (e) {
      print('AuthService initialization failed: $e');
    }
  }

  static const String _tokenKey = 'auth_token';
  static const String _tokenTypeKey = 'auth_token_type';
  static const String _usernameKey = 'auth_username';

  String? _token;
  String? _tokenType;
  String? _username;
  UserProfile? _userProfile;
  bool _isLoading = false;
  SyncResult? _lastSyncResult;

  String? get token => _token;
  String? get tokenType => _tokenType;
  String? get username => _username;
  UserProfile? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  /// 最近一次登录时本地数据同步的结果（供 UI 显示提示）
  SyncResult? get lastSyncResult => _lastSyncResult;

  /// 从本地存储加载 token
  Future<void> _loadTokenFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _tokenType = prefs.getString(_tokenTypeKey);
    _username = prefs.getString(_usernameKey);
    if (isLoggedIn) {
      ApiService.setAuthToken(_token!);
      await _fetchUserProfile();
      // _fetchUserProfile 可能因 401 触发 logout，同步前必须重新检查
      if (!isLoggedIn) {
        notifyListeners();
        return;
      }
      // 应用启动后若已登录，尝试同步上次未上传的本地记录
      try {
        _lastSyncResult = await SyncService.syncLocalToBackend()
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        print('Sync local data on startup failed: $e');
      }
    }
    notifyListeners();
  }

  /// 登录
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await ApiService.login(username, password);
      if (token != null) {
        _token = token.accessToken;
        _tokenType = token.tokenType;
        _username = username;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, _token!);
        await prefs.setString(_tokenTypeKey, _tokenType!);
        await prefs.setString(_usernameKey, username);

        ApiService.setAuthToken(_token!);
        await _fetchUserProfile();

        // 登录成功后将本地离线记录上传到后端，避免离线/在线 ID 体系混用
        try {
          _lastSyncResult = await SyncService.syncLocalToBackend();
        } catch (e) {
          print('Sync local data failed: $e');
          _lastSyncResult = null;
        }

        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      print('Login error: $e');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// 注册
  Future<bool> register(String username, String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final user = await ApiService.register(username, email, password);
      _isLoading = false;
      notifyListeners();
      return user != null;
    } catch (e) {
      print('Register error: $e');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// 获取用户信息
  Future<void> _fetchUserProfile() async {
    try {
      final profile = await ApiService.getUserProfile();
      _userProfile = profile;
      notifyListeners();
    } catch (e) {
      print('Fetch profile error: $e');
    }
  }

  /// 登出
  Future<void> logout() async {
    if (_token == null) return; // 防重入：已登出则直接返回

    _token = null;
    _tokenType = null;
    _username = null;
    _userProfile = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_tokenTypeKey);
    await prefs.remove(_usernameKey);

    ApiService.clearAuthToken();

    // 清空本地离线缓存，避免已同步数据在下次登录时重复上传
    await StorageService.clearAllLocalItems();

    notifyListeners();
  }
}

