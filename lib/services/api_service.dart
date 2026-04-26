import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' hide Category;

import '../models/category.dart';
import '../models/transaction.dart';
import '../utils/icon_utils.dart';

/// 后端 API 服务
///
/// 提供完整的 HTTP 通信、JWT 认证、所有业务 API 封装。
class ApiService {
  /// 生产服务器地址
  static const String _productionUrl = 'http://YOUR_SERVER_IP:5300';

  /// Android 模拟器访问宿主机 localhost 的地址
  static const String _emulatorUrl = 'http://10.0.2.2:5300';

  static String _baseUrl = _productionUrl;
  static bool _urlResolved = false;

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  static bool _interceptorsSetup = false;

  /// 自动探测可用后端地址。
  ///
  /// 非 Release 模式的 Android 平台会先尝试模拟器地址，
  /// 若 2 秒内无响应则回退到生产地址。避免在真机上因
  /// 10.0.2.2 不可达而导致长时间等待。
  static Future<void> _ensureBaseUrl() async {
    if (_urlResolved) return;

    if (!kReleaseMode && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final testDio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 2),
          receiveTimeout: const Duration(seconds: 2),
        ));
        await testDio.get('$_emulatorUrl/');
        _baseUrl = _emulatorUrl;
        _dio.options.baseUrl = _baseUrl;
      } catch (_) {
        // 模拟器地址不可用，继续使用生产地址
      }
    }
    _urlResolved = true;
  }

  static void _ensureInterceptors() {
    if (_interceptorsSetup) return;
    _interceptorsSetup = true;

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_authToken != null && _authToken!.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $_authToken';
        }
        return handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          // Token 过期或无效，清除认证状态并通知上层
          clearAuthToken();
          onUnauthorized?.call();
        }
        return handler.next(error);
      },
    ));
  }

  static String? _authToken;

  /// 401 未授权回调，由 AuthService 注册，用于在 token 过期时同步登出 UI 状态
  static VoidCallback? onUnauthorized;

  static Dio get dio {
    _ensureInterceptors();
    return _dio;
  }

  /// 设置认证 token
  static void setAuthToken(String token) {
    _authToken = token;
    _ensureInterceptors();
  }

  /// 清除认证 token
  static void clearAuthToken() {
    _authToken = null;
    clearCategoryCache();
  }

  /// 测试后端连通性
  static Future<void> testConnect() async {
    await _ensureBaseUrl();
    try {
      final response = await Dio().get(_baseUrl);
      print(response);
    } catch (e) {
      print(e);
    }
  }

  /// 用户登录
  ///
  /// FastAPI 的 OAuth2PasswordRequestForm 要求标准 application/x-www-form-urlencoded
  /// 编码，因此这里直接使用 Map + Headers.formUrlEncodedContentType，
  /// 让 Dio 自动按正确格式编码。
  static Future<Token?> login(String username, String password) async {
    await _ensureBaseUrl();
    try {
      final response = await _dio.post(
        '/token',
        data: {
          'username': username,
          'password': password,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      return Token.fromJson(response.data);
    } on DioException catch (e) {
      print('Login failed: ${e.response?.data}');
      return null;
    }
  }

  /// 用户注册
  static Future<UserProfile?> register(
      String username, String email, String password) async {
    await _ensureBaseUrl();
    try {
      final response = await _dio.post(
        '/users/',
        data: {
          'username': username,
          'email': email,
          'password': password,
        },
      );
      return UserProfile.fromJson(response.data);
    } on DioException catch (e) {
      // 按异常类型给出可定位的错误信息，避免一律提示"请检查网络连接"
      // 而掩盖真实失败原因（厂商防火墙拦截、TLS 失败、DNS 失败等）
      print('Register failed: type=${e.type} '
          'msg=${e.message} '
          'baseUrl=$_baseUrl '
          'resp=${e.response?.data}');
      throw Exception(_describeDioError(e, '注册'));
    } catch (e) {
      print('Register failed (non-dio): $e');
      throw Exception('注册失败：$e');
    }
  }

  /// 把 DioException 映射成对用户友好的中文提示，
  /// 同时保留足够的诊断细节用于线上排错。
  static String _describeDioError(DioException e, String action) {
    if (e.response != null) {
      final detail = e.response?.data is Map
          ? (e.response!.data as Map)['detail']
          : null;
      if (detail != null) return detail.toString();
      return '$action失败：服务器返回 ${e.response?.statusCode}';
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '$action失败：连接服务器超时，请检查网络或稍后重试';
      case DioExceptionType.sendTimeout:
        return '$action失败：请求发送超时';
      case DioExceptionType.receiveTimeout:
        return '$action失败：服务器响应超时';
      case DioExceptionType.badCertificate:
        return '$action失败：服务器证书校验失败';
      case DioExceptionType.connectionError:
        return '$action失败：无法连接服务器（${e.message ?? "网络不可达"}）。'
            '若手机首次安装请在系统设置中允许本应用联网';
      case DioExceptionType.cancel:
        return '$action已取消';
      case DioExceptionType.badResponse:
        return '$action失败：服务器响应异常 ${e.response?.statusCode}';
      case DioExceptionType.unknown:
        return '$action失败：${e.message ?? e.error ?? "未知错误"}';
    }
  }

  /// 获取当前用户信息
  static Future<UserProfile?> getUserProfile() async {
    await _ensureBaseUrl();
    try {
      final response = await dio.get('/users/me/');
      return UserProfile.fromJson(response.data);
    } on DioException catch (e) {
      print('Get profile failed: ${e.response?.data}');
      return null;
    }
  }

  // ==================== 分类 API ====================

  /// 分类列表内存缓存。getTransactions 等接口频繁调用 getCategories，
  /// 通过缓存避免每次拉取交易都要多发一次 HTTP 请求。
  static List<Category>? _categoryCache;

  /// 清除分类缓存（创建新分类或登出时调用）
  static void clearCategoryCache() {
    _categoryCache = null;
  }

  /// 获取分类列表
  static Future<List<Category>> getCategories({String? type, bool useCache = true}) async {
    await _ensureBaseUrl();
    if (useCache && type == null && _categoryCache != null) {
      return _categoryCache!;
    }
    try {
      final response = await dio.get(
        '/categories/',
        queryParameters: type != null ? {'type': type} : null,
      );
      final List data = response.data;
      final list = data.map<Category>((e) => Category.fromJson(e)).toList();
      if (type == null) {
        _categoryCache = list;
      }
      return list;
    } on DioException catch (e) {
      print('Get categories failed: ${e.response?.data}');
      return [];
    }
  }

  /// 创建分类
  static Future<Category?> createCategory(Category category) async {
    await _ensureBaseUrl();
    try {
      final response = await dio.post(
        '/categories/',
        data: {
          'name': category.name,
          'type': category.type,
          'icon': category.icon,
          'color': category.color,
        },
      );
      clearCategoryCache();
      return Category.fromJson(response.data);
    } on DioException catch (e) {
      print('Create category failed: ${e.response?.data}');
      return null;
    }
  }

  // ==================== 交易记录 API ====================

  /// 获取交易记录列表
  static Future<List<Transaction>> getTransactions({
    String? type,
    int? categoryId,
    DateTime? startDate,
    DateTime? endDate,
    int skip = 0,
    int limit = 100,
  }) async {
    await _ensureBaseUrl();
    try {
      final params = <String, dynamic>{
        'skip': skip,
        'limit': limit,
      };
      if (type != null) params['type'] = type;
      if (categoryId != null) params['category_id'] = categoryId;
      // 与提交时一致，日期参数也统一使用 UTC ISO 提交
      if (startDate != null) {
        params['start_date'] = startDate.toUtc().toIso8601String();
      }
      if (endDate != null) {
        params['end_date'] = endDate.toUtc().toIso8601String();
      }

      final response = await dio.get('/transactions/', queryParameters: params);
      final List data = response.data;

      // 先获取分类列表用于映射
      final categories = await getCategories();
      final categoryMap = <int, Category>{for (var c in categories) c.id: c};

      return data
          .map<Transaction>((e) => _transactionFromBackend(e, categoryMap))
          .toList();
    } on DioException catch (e) {
      print('Get transactions failed: ${e.response?.data}');
      return [];
    }
  }

  /// 创建交易记录
  static Future<Transaction?> createTransaction(Transaction transaction) async {
    await _ensureBaseUrl();
    try {
      final data = await _transactionToBackend(transaction);
      if (data == null) return null;

      final response = await dio.post('/transactions/', data: data);

      final categories = await getCategories();
      final categoryMap = {for (var c in categories) c.id: c};

      return _transactionFromBackend(response.data, categoryMap);
    } on DioException catch (e) {
      print('Create transaction failed: ${e.response?.data}');
      return null;
    }
  }

  /// 更新交易记录
  static Future<Transaction?> updateTransaction(
      String id, Transaction transaction) async {
    await _ensureBaseUrl();
    final intId = int.tryParse(id);
    if (intId == null) {
      print('Update transaction failed: invalid id $id');
      return null;
    }
    try {
      final data = await _transactionToBackend(transaction);
      if (data == null) return null;

      final response = await dio.put('/transactions/$intId', data: data);

      final categories = await getCategories();
      final categoryMap = {for (var c in categories) c.id: c};

      return _transactionFromBackend(response.data, categoryMap);
    } on DioException catch (e) {
      print('Update transaction failed: ${e.response?.data}');
      return null;
    }
  }

  /// 删除交易记录
  static Future<bool> deleteTransaction(String id) async {
    await _ensureBaseUrl();
    final intId = int.tryParse(id);
    if (intId == null) {
      print('Delete transaction failed: invalid id $id');
      return false;
    }
    try {
      await dio.delete('/transactions/$intId');
      return true;
    } on DioException catch (e) {
      print('Delete transaction failed: ${e.response?.data}');
      return false;
    }
  }

  // ==================== 统计 API ====================

  /// 获取财务摘要
  static Future<SummaryData?> getSummary({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    await _ensureBaseUrl();
    try {
      final params = <String, dynamic>{};
      if (startDate != null) {
        params['start_date'] = startDate.toUtc().toIso8601String();
      }
      if (endDate != null) {
        params['end_date'] = endDate.toUtc().toIso8601String();
      }

      final response = await dio.get('/summary/', queryParameters: params);
      return SummaryData.fromJson(response.data);
    } on DioException catch (e) {
      print('Get summary failed: ${e.response?.data}');
      return null;
    }
  }

  /// 获取分类统计
  static Future<CategoryStatsData?> getCategoryStats({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    await _ensureBaseUrl();
    try {
      final params = <String, dynamic>{};
      if (startDate != null) {
        params['start_date'] = startDate.toUtc().toIso8601String();
      }
      if (endDate != null) {
        params['end_date'] = endDate.toUtc().toIso8601String();
      }

      final response = await dio.get('/category-stats/', queryParameters: params);
      return CategoryStatsData.fromJson(response.data);
    } on DioException catch (e) {
      print('Get category stats failed: ${e.response?.data}');
      return null;
    }
  }

  /// 获取趋势数据
  static Future<TrendsData?> getTrends({
    String period = 'month',
    int? year,
    int? month,
    int? timezoneOffset,
  }) async {
    await _ensureBaseUrl();
    try {
      final params = <String, dynamic>{'period': period};
      if (year != null) params['year'] = year;
      if (month != null) params['month'] = month;
      if (timezoneOffset != null) {
        params['timezone_offset'] = timezoneOffset;
      }
      final response = await dio.get(
        '/trends/',
        queryParameters: params,
      );
      return TrendsData.fromJson(response.data);
    } on DioException catch (e) {
      print('Get trends failed: ${e.response?.data}');
      return null;
    }
  }

  // ==================== 数据转换 ====================

  /// 将后端交易记录转换为前端 Transaction（容错处理类型不一致）
  ///
  /// 时区约定：后端 date 字段以 UTC ISO 字符串返回（带 Z 后缀），
  /// 前端解析后调用 `.toLocal()` 转回设备本地时区显示。
  static Transaction _transactionFromBackend(
    Map<String, dynamic> json,
    Map<int, Category> categoryMap,
  ) {
    final categoryId = json['category_id'] is int
        ? json['category_id'] as int
        : int.tryParse(json['category_id']?.toString() ?? '');
    final category = categoryId != null ? categoryMap[categoryId] : null;
    final backendType = (json['type'] ?? 'expense').toString();
    final isIncome = backendType == 'income';

    // description 作为 name，如果没有则用分类名称
    final name = (json['description']?.toString().isNotEmpty == true)
        ? json['description'].toString()
        : (category?.name ?? '未知');
    // type 字段存分类名称
    final typeName = category?.name ?? '未知';

    final rawAmount = json['amount'];
    final amount = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse(rawAmount?.toString() ?? '') ?? 0.0;

    return Transaction(
      id: json['id'].toString(),
      name: name,
      type: typeName,
      amount: amount,
      isIncome: isIncome,
      date: _parseUtcAsLocal(json['date']?.toString()),
      iconCodePoint: iconNameToCodePoint(category?.icon, isIncome),
      categoryId: categoryId,
    );
  }

  /// 将后端返回的日期字符串解析为本地 DateTime。
  ///
  /// 后端约定：返回 UTC ISO 字符串（如 `2026-04-26T10:00:00Z`）。
  /// 若历史数据缺少时区后缀，则默认按 UTC 解析以维持一致性。
  static DateTime _parseUtcAsLocal(String? raw) {
    if (raw == null || raw.isEmpty) return DateTime.now();
    String s = raw;
    final hasTz = s.endsWith('Z') ||
        RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
    if (!hasTz) s = '${s}Z';
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }

  /// 将前端 Transaction 转换为后端格式
  ///
  /// 时区约定：date 统一使用 UTC ISO 字符串提交（`toUtc().toIso8601String()`），
  /// 后端 MySQL 列以 UTC naive 存储。
  ///
  /// 分类映射规则（按优先级回退，确保离线伪造 ID 也能正确同步）：
  ///   1. categoryId 命中且类型一致 → 直接使用
  ///   2. 按分类名称（transaction.type）+ 收支类型匹配
  ///   3. 兜底使用同收支类型的第一个分类
  static Future<Map<String, dynamic>?> _transactionToBackend(
      Transaction transaction) async {
    final wantedType = transaction.isIncome ? 'income' : 'expense';
    final allCategories = await getCategories();
    final candidates =
        allCategories.where((c) => c.type == wantedType).toList();

    Category? matched;

    // 1. categoryId 命中且类型一致
    if (transaction.categoryId != null) {
      for (final c in allCategories) {
        if (c.id == transaction.categoryId && c.type == wantedType) {
          matched = c;
          break;
        }
      }
    }

    // 2. 按分类名称匹配（处理离线本地伪造 ID 的情况）
    if (matched == null) {
      for (final c in candidates) {
        if (c.name == transaction.type) {
          matched = c;
          break;
        }
      }
    }

    // 3. 兜底取同类型第一个
    matched ??= candidates.isNotEmpty ? candidates.first : null;

    if (matched == null) {
      print('No matching category for sync: '
          'type=$wantedType name=${transaction.type}');
      return null;
    }

    return {
      'amount': transaction.amount,
      'type': wantedType,
      'description': transaction.name,
      'date': transaction.date.toUtc().toIso8601String(),
      'category_id': matched.id,
    };
  }

}

class Token {
  final String accessToken;
  final String tokenType;

  Token({required this.accessToken, required this.tokenType});

  factory Token.fromJson(Map<String, dynamic> json) {
    return Token(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String,
    );
  }
}

class UserProfile {
  final int id;
  final String username;
  final String email;

  UserProfile({required this.id, required this.username, required this.email});

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,
    );
  }
}

/// 财务摘要数据
class SummaryData {
  final double income;
  final double expense;
  final double balance;
  final double incomeChange;
  final double expenseChange;
  final double balanceChange;

  SummaryData({
    required this.income,
    required this.expense,
    required this.balance,
    required this.incomeChange,
    required this.expenseChange,
    required this.balanceChange,
  });

  factory SummaryData.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    return SummaryData(
      income: toDouble(json['income']),
      expense: toDouble(json['expense']),
      balance: toDouble(json['balance']),
      incomeChange: toDouble(json['income_change']),
      expenseChange: toDouble(json['expense_change']),
      balanceChange: toDouble(json['balance_change']),
    );
  }
}

/// 分类统计数据
class CategoryStatsData {
  final List<String> labels;
  final List<double> values;
  final List<String> colors;
  final List<double> amounts;

  CategoryStatsData({
    required this.labels,
    required this.values,
    required this.colors,
    required this.amounts,
  });

  factory CategoryStatsData.fromJson(Map<String, dynamic> json) {
    return CategoryStatsData(
      labels: (json['labels'] as List).cast<String>(),
      values: (json['values'] as List).map((e) {
        if (e is num) return e.toDouble();
        if (e is String) return double.tryParse(e) ?? 0.0;
        return 0.0;
      }).toList(),
      colors: (json['colors'] as List).cast<String>(),
      amounts: (json['amounts'] as List).map((e) {
        if (e is num) return e.toDouble();
        if (e is String) return double.tryParse(e) ?? 0.0;
        return 0.0;
      }).toList(),
    );
  }
}

/// 趋势数据
class TrendsData {
  final List<String> labels;
  final List<double> income;
  final List<double> expense;

  TrendsData({
    required this.labels,
    required this.income,
    required this.expense,
  });

  factory TrendsData.fromJson(Map<String, dynamic> json) {
    return TrendsData(
      labels: (json['labels'] as List).cast<String>(),
      income: (json['income'] as List).map((e) {
        if (e is num) return e.toDouble();
        if (e is String) return double.tryParse(e) ?? 0.0;
        return 0.0;
      }).toList(),
      expense: (json['expense'] as List).map((e) {
        if (e is num) return e.toDouble();
        if (e is String) return double.tryParse(e) ?? 0.0;
        return 0.0;
      }).toList(),
    );
  }
}
