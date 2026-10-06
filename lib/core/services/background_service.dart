import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../firebase_options.dart';

@pragma('vm:entry-point')
class BackgroundService {
  BackgroundService._();
  static final BackgroundService instance = BackgroundService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();

  /// Инициализация конфигурации сервиса (один раз при старте приложения)
  Future<void> initialize() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: true,
        isForegroundMode: true,
        autoStartOnBoot: true,
        foregroundServiceTypes: [AndroidForegroundType.specialUse],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  /// Запуск сервиса
  Future<void> start() async {
    final isRunning = await _service.isRunning();
    if (!isRunning) {
      await _service.startService();
    }
  }

  /// Остановка сервиса (например, при выходе из аккаунта)
  Future<void> stop() async {
    _service.invoke('stop');
  }

  /// Точка входа для Android foreground service
  /// ВАЖНО: top-level / static функция с @pragma
  @pragma('vm:entry-point')
  static Future<void> _onStart(ServiceInstance service) async {
    // Инициализация плагинов в изоляте сервиса
    DartPluginRegistrant.ensureInitialized();

    // Инициализация Firebase в изоляте
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Показываем постоянное уведомление (обязательно для foreground service)
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Сборка заказов',
        content: 'Отслеживание новых заказов активно',
      );
    }

    // Подписка на push-сообщения внутри сервиса
    FirebaseMessaging.onMessage.listen((message) {
      print('📩 [BG Service] Получен push: ${message.notification?.title}');

      // Логируем задержку
      if (message.sentTime != null) {
        final delay = DateTime.now().difference(message.sentTime!);
        print('⏱ [BG Service] Задержка: ${delay.inSeconds} сек');
      }
    });

    // Команда остановки от основного процесса
    service.on('stop').listen((event) {
      service.stopSelf();
    });

    print('✅ [BG Service] Foreground service запущен');
  }

  /// iOS background handler
  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    return true;
  }
}