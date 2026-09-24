import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:sborapps/firebase_options.dart';

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  static const String _ordersChannelId = 'orders_channel';
  static const String _ordersChannelName = 'Новые заказы';
  static const String _ordersChannelDescription =
      'Уведомления о новых заказах';

  static const String _serviceChannelId = 'orders_service_channel';
  static const int _serviceNotificationId = 888;

  String? _deviceToken;
  String? get deviceToken => _deviceToken;

  bool _initialized = false;

  /// Вызывать после Firebase.initializeApp() в main().
  Future<void> initialize() async {
    if (_initialized) return;

    await _requestPermissions();
    await _initLocalNotifications();

    if (Platform.isIOS) {
      // Foreground FCM показываем через локальное уведомление, без дубля.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
    }

    _messaging.onTokenRefresh.listen((newToken) {
      _deviceToken = newToken;
      debugPrint('FCM токен обновлён: $newToken');
      // TODO: Отправить новый токен на свой сервер.
    });

    _setupMessageHandlers();
    _initialized = true;
    await _getToken();
  }

  Future<void> _requestPermissions() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _initLocalNotifications() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _localNotifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (Platform.isAndroid) {
      const ordersChannel = AndroidNotificationChannel(
        _ordersChannelId,
        _ordersChannelName,
        description: _ordersChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(ordersChannel);
    }

    final launchDetails =
    await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      debugPrint(
        'Открыто из локального уведомления: '
            '${launchDetails?.notificationResponse?.payload}',
      );
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Тап по локальному уведомлению: ${response.payload}');
    // TODO: Открыть заказ по order_id из response.payload.
  }

  Future<void> _getToken() async {
    try {
      _deviceToken = await _messaging.getToken();
      debugPrint('FCM токен устройства: $_deviceToken');
      // TODO: Отправить токен на свой сервер.
    } catch (e) {
      debugPrint('Ошибка получения FCM токена: $e');
    }
  }

  void _setupMessageHandlers() {
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('Foreground сообщение: ${message.notification?.title}');
      _showLocalNotification(message).catchError((Object error) {
        debugPrint('Ошибка показа уведомления: $error');
      });
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('Тап по FCM уведомлению из фона: ${message.data}');
      // TODO: Открыть заказ по message.data['order_id'].
    });

    _messaging.getInitialMessage().then((message) {
      if (message != null) {
        debugPrint('Открыто из FCM уведомления: ${message.data}');
        // TODO: Открыть заказ по message.data['order_id'].
      }
    }).catchError((Object error) {
      debugPrint('Ошибка getInitialMessage: $error');
    });
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) {
      debugPrint('FCM сообщение без notification payload: ${message.data}');
      return;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _ordersChannelId,
        _ordersChannelName,
        channelDescription: _ordersChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    final id = DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
    final payload = message.data['order_id']?.toString();

    await _localNotifications.show(
      id: id,
      title: notification.title,
      body: notification.body,
      notificationDetails: details,
      payload: payload,
    );

    debugPrint('Локальное уведомление показано: id=$id');
  }

  /// Не нужен для обычной доставки FCM. Запускать отдельно,
  /// только если есть реальная длительная задача синхронизации на Android.
  Future<void> startForegroundService() async {
    if (!Platform.isAndroid) return;

    const serviceChannel = AndroidNotificationChannel(
      _serviceChannelId,
      'Синхронизация заказов',
      description: 'Постоянное уведомление фонового сервиса',
      importance: Importance.low,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(serviceChannel);

    final service = FlutterBackgroundService();
    if (await service.isRunning()) return;

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onOrdersServiceStart,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        foregroundServiceNotificationId: _serviceNotificationId,
        notificationChannelId: _serviceChannelId,
        initialNotificationTitle: 'Сборка заказов активна',
        initialNotificationContent: 'Синхронизация заказов...',
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );

    await service.startService();
  }

  void stopForegroundService() {
    if (!Platform.isAndroid) return;
    FlutterBackgroundService().invoke('stopService');
  }
}

// Callback должен быть вне класса и не внутри _showLocalNotification().
@pragma('vm:entry-point')
Future<void> onOrdersServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Это разовое получение токена, а не механизм доставки FCM-сообщений.
    final token = await FirebaseMessaging.instance.getToken();
    debugPrint('[BG Service] FCM токен: $token');
  } catch (e) {
    debugPrint('[BG Service] Ошибка Firebase: $e');
  }

  // TODO: Если нужен foreground service, добавьте здесь реальную
  // продолжительную работу. Для ожидания пушей FCM сервис не нужен.
}