import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminAuthService {
  static const String _baseUrl = 'https://dagix.ru/BrBulvar/sbor_api';
  static const String _tokenKey = 'admin_token';
  static const String _adminKey = 'admin_data';
  static const Duration _timeout = Duration(seconds: 30);

  // Debug flag
  static const bool _debug = true;

  static void _log(String message) {
    if (_debug) {
      print('🔵 [AdminAuthService] $message');
    }
  }

  static void _logError(String message, Object? error) {
    if (_debug) {
      print('❌ [AdminAuthService] ERROR: $message');
      if (error != null) {
        print('   Details: $error');
      }
    }
  }

  static void _logSuccess(String message) {
    if (_debug) {
      print('✅ [AdminAuthService] SUCCESS: $message');
    }
  }

  // ============================================
  // ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================================

  /// Безопасный парсинг JSON
  static Map<String, dynamic>? _safeJsonDecode(String body) {
    if (body.isEmpty) {
      _logError('JSON Parse', 'Тело ответа пусто');
      return null;
    }

    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      _logError('JSON Parse Error', 'Невалидный JSON: $e\nТело: $body');
      return null;
    }
  }

  // ============================================
  // АВТОРИЗАЦИЯ
  // ============================================

  /// Вход администратора
  static Future<AdminLoginResponse> login(
      String username,
      String password,
      ) async {
    _log('🔐 Начало входа для пользователя: $username');
    _log('📍 URL: $_baseUrl/admin_auth_api.php?action=login');

    try {
      final url = '$_baseUrl/admin_auth_api.php?action=login';
      _log('📤 Отправка POST запроса...');
      _log('📦 Тело запроса: username=$username, password=***');

      final response = await http
          .post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      )
          .timeout(_timeout, onTimeout: () {
        _logError('Timeout', 'Сервер не ответил за 30 секунд');
        throw TimeoutException('Timeout при подключении к серверу');
      });

      _log('📥 Получен ответ со статусом: ${response.statusCode}');
      _log('📄 Размер тела: ${response.body.length} байт');

      if (response.body.isNotEmpty) {
        _log('📄 Первые 200 символов: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
      }

      // Проверка на ошибку 500
      if (response.statusCode == 500) {
        _logError('Server Error 500', 'Сервер вернул ошибку');

        if (response.body.isEmpty) {
          throw AdminAuthException(
            'Ошибка сервера (500). Проверьте логи PHP на сервере.',
            500,
          );
        }

        final data = _safeJsonDecode(response.body);
        if (data != null) {
          throw AdminAuthException(
            data['error'] ?? 'Ошибка сервера',
            500,
          );
        } else {
          throw AdminAuthException(
            'Ошибка сервера 500. Тело ответа невалидно.',
            500,
          );
        }
      }

      final data = _safeJsonDecode(response.body);

      if (data == null) {
        throw AdminAuthException(
          'Невалидный ответ сервера',
          response.statusCode,
        );
      }

      _log('🔍 Parsed JSON: $data');

      if (response.statusCode == 200 && data['success'] == true) {
        _logSuccess('Авторизация успешна для $username');

        // Сохранить токен и данные админа
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, data['token']);
        await prefs.setString(_adminKey, jsonEncode(data['admin']));

        _log('💾 Данные сохранены в SharedPreferences');
        _log('🎫 Токен: ${data['token'].toString().substring(0, 20)}...');

        return AdminLoginResponse.fromJson(data);
      } else {
        _logError('Ошибка авторизации',
            'Status: ${response.statusCode}, Response: ${data['error'] ?? 'Unknown error'}');
        throw AdminAuthException(
          data['error'] ?? 'Ошибка входа',
          response.statusCode,
        );
      }
    } on TimeoutException catch (e) {
      _logError('Timeout Exception', e.message);
      throw AdminAuthException(
        'Сервер не отвечает. Проверьте соединение и адрес API.',
        408,
      );
    } catch (e) {
      _logError('Exception', e);
      throw AdminAuthException('Ошибка сети: $e');
    }
  }

  /// Выход администратора
  static Future<void> logout() async {
    _log('🔓 Начало выхода...');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);

      _log('🎫 Найденный токен: ${token?.substring(0, 20) ?? 'Not found'}...');

      if (token != null) {
        final url = '$_baseUrl/admin_auth_api.php?action=logout';
        _log('📍 URL: $url');
        _log('📤 Отправка logout запроса...');

        final response = await http
            .post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({'token': token}),
        )
            .timeout(_timeout);

        _log('📥 Ответ: ${response.statusCode}');
        _log('📄 Тело: ${response.body}');
      }

      // Удалить локальные данные
      await prefs.remove(_tokenKey);
      await prefs.remove(_adminKey);

      _logSuccess('Выход завершен, данные удалены');
    } catch (e) {
      _logError('Exception при выходе', e);
      throw AdminAuthException('Ошибка выхода: $e');
    }
  }

  /// Проверить токен
  static Future<Admin> verifyToken() async {
    _log('✔️ Начало проверки токена...');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);

      if (token == null) {
        _log('⚠️ Токен не найден в SharedPreferences');
        throw AdminAuthException('Токен не найден', 401);
      }

      _log('🎫 Токен найден: ${token.substring(0, 20)}...');

      final url = '$_baseUrl/admin_auth_api.php?action=verify_token&token=$token';
      _log('📍 URL: $url');
      _log('📤 Отправка GET запроса...');

      final response = await http
          .get(Uri.parse(url))
          .timeout(_timeout, onTimeout: () {
        _logError('Timeout', 'Сервер не ответил при проверке токена');
        throw TimeoutException('Timeout при проверке токена');
      });

      _log('📥 Ответ: ${response.statusCode}');
      _log('📄 Тело: ${response.body}');

      final data = _safeJsonDecode(response.body);

      if (data == null) {
        throw AdminAuthException(
          'Невалидный ответ сервера при проверке токена',
          response.statusCode,
        );
      }

      if (response.statusCode == 200 && data['success'] == true) {
        _logSuccess('Токен действителен');
        return Admin.fromJson(data['admin']);
      } else {
        _logError('Токен недействителен', data['error']);
        throw AdminAuthException(
          data['error'] ?? 'Токен недействителен',
          response.statusCode,
        );
      }
    } on TimeoutException catch (e) {
      _logError('Timeout Exception', e.message);
      throw AdminAuthException(
        'Сервер не отвечает при проверке токена',
        408,
      );
    } catch (e) {
      _logError('Exception при проверке токена', e);
      throw AdminAuthException('Ошибка проверки токена: $e');
    }
  }

  /// Изменить пароль
  static Future<void> changePassword(
      String oldPassword,
      String newPassword,
      ) async {
    _log('🔑 Начало изменения пароля...');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);

      if (token == null) {
        _logError('Токен не найден', null);
        throw AdminAuthException('Токен не найден', 401);
      }

      final url = '$_baseUrl/admin_auth_api.php?action=change_password';
      _log('📍 URL: $url');
      _log('📤 Отправка запроса на изменение пароля...');

      final response = await http
          .post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'token': token,
          'old_password': oldPassword,
          'new_password': newPassword,
        }),
      )
          .timeout(_timeout);

      _log('📥 Ответ: ${response.statusCode}');
      _log('📄 Тело: ${response.body}');

      final data = _safeJsonDecode(response.body);

      if (data == null) {
        throw AdminAuthException(
          'Невалидный ответ сервера при изменении пароля',
          response.statusCode,
        );
      }

      if (response.statusCode != 200 || data['success'] != true) {
        _logError('Ошибка при изменении пароля', data['error']);
        throw AdminAuthException(
          data['error'] ?? 'Ошибка изменения пароля',
          response.statusCode,
        );
      }

      _logSuccess('Пароль успешно изменен');
    } catch (e) {
      _logError('Exception при изменении пароля', e);
      throw AdminAuthException('Ошибка изменения пароля: $e');
    }
  }

  /// Получить сохраненный токен
  static Future<String?> getToken() async {
    _log('🔍 Получение токена из SharedPreferences...');

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);

    if (token != null) {
      _log('✅ Токен найден: ${token.substring(0, 20)}...');
    } else {
      _log('⚠️ Токен не найден');
    }

    return token;
  }

  /// Получить сохраненного админа
  static Future<Admin?> getSavedAdmin() async {
    _log('👤 Получение данных админа из SharedPreferences...');

    try {
      final prefs = await SharedPreferences.getInstance();
      final adminJson = prefs.getString(_adminKey);

      if (adminJson == null) {
        _log('⚠️ Данные админа не найдены');
        return null;
      }

      final admin = Admin.fromJson(jsonDecode(adminJson));
      _logSuccess('Данные админа найдены: ${admin.username}');

      return admin;
    } catch (e) {
      _logError('Exception при получении данных админа', e);
      return null;
    }
  }

  /// Проверить авторизацию
  static Future<bool> isAuthenticated() async {
    _log('🔐 Проверка авторизации...');

    final token = await getToken();

    if (token == null) {
      _log('⚠️ Токен не найден - пользователь не авторизован');
      return false;
    }

    try {
      await verifyToken();
      _logSuccess('Пользователь авторизован');
      return true;
    } catch (e) {
      _log('⚠️ Токен недействителен - пользователь не авторизован');
      return false;
    }
  }

// ============================================
// МОДЕЛИ
// ============================================
}

class Admin {
  final int id;
  final String username;
  final String email;
  final String fullName;
  final String role;
  final String? phone;

  Admin({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    required this.role,
    this.phone,
  });

  factory Admin.fromJson(Map json) {
    return Admin(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      role: json['role'] as String,
      phone: json['phone'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'full_name': fullName,
      'role': role,
      'phone': phone,
    };
  }

  bool get isSuperAdmin => role == 'superadmin';
  bool get isAdmin => role == 'admin' || role == 'superadmin';
  bool get isManager =>
      role == 'manager' || role == 'admin' || role == 'superadmin';
}

class AdminLoginResponse {
  final bool success;
  final String message;
  final String token;
  final Admin admin;
  final DateTime expiresAt;

  AdminLoginResponse({
    required this.success,
    required this.message,
    required this.token,
    required this.admin,
    required this.expiresAt,
  });

  factory AdminLoginResponse.fromJson(Map json) {
    return AdminLoginResponse(
      success: json['success'] as bool,
      message: json['message'] as String,
      token: json['token'] as String,
      admin: Admin.fromJson(json['admin'] as Map),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

class AdminAuthException implements Exception {
  final String message;
  final int? statusCode;

  AdminAuthException(this.message, [this.statusCode]);

  @override
  String toString() =>
      'AdminAuthException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
}

class TimeoutException implements Exception {
  final String message;

  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
