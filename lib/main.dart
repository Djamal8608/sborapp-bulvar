import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'app.dart';
import 'core/services/app_config.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/background_service.dart';
import 'firebase_options.dart';

/// Обработчик фоновых push-сообщений (когда приложение закрыто)
///
/// ВАЖНО: top-level функция с @pragma — выполняется в отдельном изоляте
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Инициализация Firebase в фоновом изоляте (обязательно!)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  print('📩 [BG] Получено фоновое сообщение: ${message.messageId}');
  print('📩 [BG] Title: ${message.notification?.title}');
  print('📩 [BG] Data: ${message.data}');
  print('📩 [BG] Sent time: ${message.sentTime}');

  // Логируем задержку доставки (для диагностики проблемы 2 минут)
  if (message.sentTime != null) {
    final delay = DateTime.now().difference(message.sentTime!);
    print('⏱ [BG] Задержка доставки: ${delay.inSeconds} сек');
  }
}

Future<void> main() async {
  // 1. Обязательно для асинхронных операций ДО runApp
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Инициализация Firebase (ПЕРЕД всем остальным!)
  bool firebaseOk = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseOk = true;
    debugPrint('✅ Firebase инициализирован');
  } catch (e) {
    debugPrint('❌ Ошибка инициализации Firebase: $e');
  }

  // 3. Регистрируем обработчик фоновых сообщений (только если Firebase OK)
  if (firebaseOk) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    debugPrint('✅ Обработчик фоновых сообщений зарегистрирован');
  }

  // 4. Загружаем .env файл
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('⚠ .env не загружен (будут использованы --dart-define): $e');
  }

  // 5. Логирование конфига в dev-режиме
  if (AppConfig.isDevelopment) {
    debugPrint('🔧 AppConfig loaded:');
    debugPrint('  API_BASE_URL: ${AppConfig.apiBaseUrl}');
    debugPrint('  GATEWAY_URL:  ${AppConfig.gatewayUrl}');
    debugPrint('  GATEWAY_SECRET: ${'•' * AppConfig.gatewaySecret.length}');
    debugPrint('  FLAVOR: ${AppConfig.isDevelopment ? 'development' : 'production'}');
  }

  // 6. Проверяем критичные секреты
  if (AppConfig.gatewaySecret.isEmpty) {
    debugPrint('⚠⚠⚠ ВНИМАНИЕ: GATEWAY_SECRET не настроен!');
    debugPrint('Создайте .env файл на основе .env.example');
  }

  // 7. Инициализация сервиса push-уведомлений
  if (firebaseOk) {
    try {
      await PushNotificationService.instance.initialize();
      debugPrint('✅ PushNotificationService инициализирован');

      // Логируем токен для отладки
      final token = PushNotificationService.instance.deviceToken;
      if (token != null) {
        debugPrint('📱 FCM токен: $token');
      }
    } catch (e) {
      debugPrint('❌ Ошибка инициализации push-уведомлений: $e');
    }

    // 8. ✅ НОВОЕ: Запуск foreground service для мгновенной доставки пушей
    // Это решает проблему задержки в 2 минуты на Android
    try {
      await BackgroundService.instance.initialize();
      await BackgroundService.instance.start();
      debugPrint('✅ Background service запущен');
    } catch (e) {
      debugPrint('⚠ Не удалось запустить background service: $e');
      // Не критично — пуши всё равно будут приходить, но с задержкой
    }
  }

  // 9. Запускаем приложение
  runApp(const OrderPickerApp());
}