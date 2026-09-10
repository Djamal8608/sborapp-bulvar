import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app.dart';
import 'core/services/app_config.dart';

Future<void> main() async {
  // 1. Обязательно для асинхронных операций ДО runApp
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Загружаем .env файл (в release-сборке это будет работать
  //    через --dart-define, а .env просто не будет использован)
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    // Если .env не найден (например, в release-сборке) — не проблема,
    // значения возьмутся из --dart-define
    debugPrint('⚠ .env не загружен (будут использованы --dart-define): $e');
  }

  // 3. Логирование конфига в dev-режиме (удобно для отладки)
  if (AppConfig.isDevelopment) {
    debugPrint('🔧 AppConfig loaded:');
    debugPrint('  API_BASE_URL: ${AppConfig.apiBaseUrl}');
    debugPrint('  GATEWAY_URL:  ${AppConfig.gatewayUrl}');
    debugPrint('  GATEWAY_SECRET: ${'•' * AppConfig.gatewaySecret.length}');
    debugPrint('  FLAVOR: ${AppConfig.isDevelopment ? 'development' : 'production'}');
  }

  // 4. Проверяем критичные секреты
  if (AppConfig.gatewaySecret.isEmpty) {
    debugPrint('⚠⚠⚠ ВНИМАНИЕ: GATEWAY_SECRET не настроен!');
    debugPrint('Создайте .env файл на основе .env.example');
  }

  // 5. Запускаем приложение
  runApp(const OrderPickerApp());
}