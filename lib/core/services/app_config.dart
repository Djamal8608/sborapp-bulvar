import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Централизованное хранилище конфигурации приложения.
///
/// Приоритет источников (от высшего к низшему):
/// 1. `--dart-define` (переменные времени компиляции, для prod-сборок)
/// 2. `.env` файл (для локальной разработки)
/// 3. Значения по умолчанию (fallback)
class AppConfig {
  AppConfig._();

  /// Возвращает значение переменной с приоритетом:
  /// --dart-define > .env > defaultValue
  static String _get(String key, {String defaultValue = ''}) {
    // 1. Сначала проверяем --dart-define (compile-time)
    const dartDefineValue = String.fromEnvironment('');
    // Для конкретного ключа используем именованный параметр
    final fromEnv = dotenv.env[key] ?? '';

    return fromEnv.isNotEmpty ? fromEnv : defaultValue;
  }

  /// Секрет для OData-шлюза
  static String get gatewaySecret {
    const value = String.fromEnvironment('GATEWAY_SECRET');
    if (value.isNotEmpty) return value;
    return dotenv.env['GATEWAY_SECRET'] ?? '';
  }

  /// Базовый URL API сборщика
  static String get apiBaseUrl {
    const value = String.fromEnvironment('API_BASE_URL');
    if (value.isNotEmpty) return value;
    return dotenv.env['API_BASE_URL'] ?? 'https://dagix.ru/BrBulvar/sbor_api';
  }

  /// URL OData-шлюза
  static String get gatewayUrl {
    const value = String.fromEnvironment('GATEWAY_URL');
    if (value.isNotEmpty) return value;
    return dotenv.env['GATEWAY_URL'] ?? 'https://dagix.ru/BrBulvar/gateway_odata.php';
  }

  /// Флаг разработки (true если нет --dart-define FLAVOR=production)
  static bool get isDevelopment {
    const flavor = String.fromEnvironment('FLAVOR');
    return flavor != 'production';
  }
}