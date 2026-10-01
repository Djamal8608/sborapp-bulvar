import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:sborapps/core/services/api_service.dart';
import 'package:sborapps/firebase_options.dart';

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance =
  PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  // Этот ID совпадает с channel_id в PHP NotificationService.
  static const String _ordersChannelId = 'orders_channel';
  static const String _ordersChannelName = 'Заказы';
  static const String _ordersChannelDescription =
      'Новые заказы и напоминания о непринятых заказах';

  static const String _serviceChannelId = 'orders_service_channel';
  static const int _serviceNotificationId = 888;

  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  String? _deviceToken;
  String? get deviceToken => _deviceToken;

  bool _initialized = false;
  Future<void>? _initializationFuture;

  // Не используем ID уведомления фонового сервиса.
  int _notificationCounter = 10000;

  // Необязательный обработчик нажатия на локальное уведомление.
  // Навигацию назначает приложение, у которого есть BuildContext.
  void Function(int orderId)? onLocalNotificationTap;

  int? _pendingLocalOrderId;

  /// Получить заказ, открытый локальным уведомлением до готовности UI.
  /// После чтения значение очищается.
  int? takePendingLocalOrderId() {
    final orderId = _pendingLocalOrderId;
    _pendingLocalOrderId = null;
    return orderId;
  }

  /// Вызывать после Firebase.initializeApp().
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final runningInitialization = _initializationFuture;
    if (runningInitialization != null) {
      await runningInitialization;
      return;
    }

    final initialization = _initializeInternal();
    _initializationFuture = initialization;

    try {
      await initialization;
    } finally {
      _initializationFuture = null;
    }
  }

  Future<void> _initializeInternal() async {
    await _requestPermissions();
    await _initLocalNotifications();

    if (Platform.isIOS) {
      // Показываем foreground FCM через локальные уведомления.
      // Отключаем второй, системный foreground-показ.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
    }

    _setupMessageHandlers();
    _setupTokenRefreshHandler();

    await _getToken();

    _initialized = true;
    debugPrint('[Push] Сервис уведомлений инициализирован');
  }

  Future<void> _requestPermissions() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint(
      '[Push] Разрешение на уведомления: '
          '${settings.authorizationStatus}',
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
      final androidPlugin =
      _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      const ordersChannel = AndroidNotificationChannel(
        _ordersChannelId,
        _ordersChannelName,
        description: _ordersChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await androidPlugin?.createNotificationChannel(ordersChannel);
    }

    // Запуск приложения через локальное уведомление.
    final launchDetails =
    await _localNotifications.getNotificationAppLaunchDetails();

    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final payload = launchDetails?.notificationResponse?.payload;
      _pendingLocalOrderId = int.tryParse(payload ?? '');

      debugPrint(
        '[Push] Запуск из локального уведомления: '
            'orderId=$_pendingLocalOrderId',
      );
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    final orderId = int.tryParse(response.payload ?? '');

    if (orderId == null) {
      return;
    }

    debugPrint('[Push] Тап по локальному уведомлению: orderId=$orderId');

    final callback = onLocalNotificationTap;

    if (callback != null) {
      callback(orderId);
    } else {
      _pendingLocalOrderId = orderId;
    }

    // Нажатие не означает принятие заказа.
    // Повторы прекращает сервер после изменения orders.status.
  }

  Future<void> _getToken() async {
    try {
      _deviceToken = await _messaging.getToken();

      if (_deviceToken == null || _deviceToken!.isEmpty) {
        debugPrint('[Push] FCM токен пока недоступен');
        return;
      }

      debugPrint('[Push] FCM токен получен');

      // Первичную регистрацию после входа выполняет OrdersScreen.
      // Здесь не отправляем запрос, поскольку пользователь
      // во время initialize() может быть ещё не авторизован.
    } catch (e) {
      debugPrint('[Push] Ошибка получения FCM токена: $e');
    }
  }

  void _setupTokenRefreshHandler() {
    if (_tokenRefreshSubscription != null) {
      return;
    }

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
          (newToken) async {
        _deviceToken = newToken;

        debugPrint('[Push] FCM токен обновлён');

        await _registerTokenOnServer(newToken);
      },
      onError: (Object error) {
        debugPrint('[Push] Ошибка обновления FCM токена: $error');
      },
    );
  }

  Future<void> _registerTokenOnServer(String token) async {
    if (token.isEmpty) {
      return;
    }

    try {
      await ApiService.registerDeviceToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );

      debugPrint('[Push] FCM токен зарегистрирован на сервере');
    } catch (e) {
      // Например, пользователь ещё не вошёл.
      // Повторить регистрацию можно после авторизации.
      debugPrint('[Push] Не удалось зарегистрировать FCM токен: $e');
    }
  }

  /// Можно вызывать после авторизации или при возврате в приложение.
  Future<void> registerCurrentDeviceToken() async {
    try {
      final token = await _messaging.getToken();

      if (token == null || token.isEmpty) {
        debugPrint('[Push] Нет FCM токена для регистрации');
        return;
      }

      _deviceToken = token;

      await _registerTokenOnServer(token);
    } catch (e) {
      debugPrint('[Push] Ошибка регистрации текущего FCM токена: $e');
    }
  }

  void _setupMessageHandlers() {
    if (_messageSubscription != null) {
      return;
    }

    // Только показ foreground-уведомления.
    // OrdersScreen отдельно обновляет список заказов.
    _messageSubscription = FirebaseMessaging.onMessage.listen(
          (message) async {
        debugPrint(
          '[Push] Foreground FCM: '
              'type=${message.data['type']}, '
              'orderId=${message.data['order_id']}',
        );

        try {
          await _showLocalNotification(message);
        } catch (e) {
          debugPrint('[Push] Ошибка показа уведомления: $e');
        }
      },
      onError: (Object error) {
        debugPrint('[Push] Ошибка получения foreground FCM: $error');
      },
    );

    // onMessageOpenedApp и getInitialMessage остаются в OrdersScreen.
    // Здесь не добавляем дублирующие обработчики.
  }

  int _nextNotificationId() {
    _notificationCounter++;

    if (_notificationCounter >= 2147483647) {
      _notificationCounter = 10000;
    }

    return _notificationCounter;
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;

    if (notification == null) {
      debugPrint(
        '[Push] Сообщение без notification payload: '
            'type=${message.data['type']}',
      );
      return;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _ordersChannelId,
        _ordersChannelName,
        channelDescription: _ordersChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        onlyAlertOnce: false,
        ongoing: false,
        autoCancel: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    final id = _nextNotificationId();

    await _localNotifications.show(
      id: id,
      title: notification.title,
      body: notification.body,
      notificationDetails: details,
      payload: message.data['order_id']?.toString(),
    );

    debugPrint('[Push] Локальное уведомление показано: id=$id');
  }

  // Методы совместимости со старым OrdersScreen.
  // Локальные таймеры отключены: повторы выполняет PHP cron.

  void startReminderForOrder(
      int orderId,
      String title,
      String body,
      ) {
    // Намеренно ничего не запускаем.
  }

  void stopReminderForOrder(int orderId) {
    // Локальных таймеров больше нет.
  }

  void stopAllReminders() {
    // Локальных таймеров больше нет.
  }

  /// Сохранён для совместимости.
  /// Не вызывать только ради получения push.
  Future<void> startForegroundService() async {
    if (!Platform.isAndroid) {
      return;
    }

    const serviceChannel = AndroidNotificationChannel(
      _serviceChannelId,
      'Синхронизация заказов',
      description: 'Постоянное уведомление фонового сервиса',
      importance: Importance.low,
    );

    final androidPlugin =
    _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(serviceChannel);

    final service = FlutterBackgroundService();

    if (await service.isRunning()) {
      return;
    }

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
        foregroundServiceTypes: [
          AndroidForegroundType.dataSync,
        ],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
      ),
    );

    await service.startService();
  }

  void stopForegroundService() {
    if (!Platform.isAndroid) {
      return;
    }

    FlutterBackgroundService().invoke('stopService');
  }
}

@pragma('vm:entry-point')
Future<void> onOrdersServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    debugPrint('[BG Service] Firebase инициализирован');
  } catch (e) {
    debugPrint('[BG Service] Ошибка Firebase: $e');
  }

  // Здесь нет повторных напоминаний.
  // Если foreground service действительно используется,
  // его задачу синхронизации нужно реализовать отдельно.
}