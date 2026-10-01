import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sborapps/core/services/api_service.dart';
import 'package:sborapps/core/services/push_notification_service.dart';
import 'package:sborapps/ui/screens/order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({Key? key}) : super(key: key);

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with WidgetsBindingObserver {
  late Future<List<Order>> _ordersFuture;

  /// Подписка на foreground push-уведомления
  StreamSubscription<RemoteMessage>? _messageSubscription;

  /// Подписка на тап по уведомлению (когда приложение было в фоне)
  StreamSubscription<RemoteMessage>? _openedAppSubscription;

  /// Флаг "есть ли уже загруженные данные" — для тихого обновления
  bool _hasLoadedData = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Первая загрузка
    _ordersFuture = ApiService.getOrders().then((orders) {
      if (mounted) {
        setState(() => _hasLoadedData = true);
      }
      return orders;
    }).catchError((e) {
      // Даже при ошибке считаем, что данные "загружались"
      if (mounted) {
        setState(() => _hasLoadedData = true);
      }
      throw e;
    });

    // ✅ Подписка на push-уведомления
    _setupPushNotifications();

    // ✅ Регистрируем device token на бэкенде
    _registerDeviceToken();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _messageSubscription?.cancel();
    _openedAppSubscription?.cancel();

    final pushService = PushNotificationService.instance;

    if (pushService.onLocalNotificationTap == _handleLocalNotificationTap) {
      pushService.onLocalNotificationTap = null;
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      _silentRefresh();
      _registerDeviceToken();
    }
  }

  /// Настройка подписок на push-уведомления
  void _setupPushNotifications() {
    // Сервис показывает foreground-уведомление.
    // Здесь только обновляем список заказов.
    _messageSubscription = FirebaseMessaging.onMessage.listen((message) {
      if (!mounted) return;

      final type = message.data['type']?.toString();

      debugPrint('[OrdersScreen] Foreground push: type=$type');

      if (
      type == 'new_order' ||
          type == 'order_reminder' ||
          type == 'order_updated' ||
          type == 'order_accepted' ||
          type == 'order_rejected') {
        _silentRefresh();
      }
    });

    // Нажатие на системное FCM-уведомление из фона.
    _openedAppSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          if (!mounted) return;

          _handleNotificationTap(message);
        });

    // Нажатие на локальное foreground-уведомление.
    PushNotificationService.instance.onLocalNotificationTap =
        _handleLocalNotificationTap;

    // Запуск закрытого приложения через системное FCM-уведомление.
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (!mounted || message == null) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        _handleNotificationTap(message);
      });
    }).catchError((Object error) {
      debugPrint(
        '[OrdersScreen] Ошибка getInitialMessage: $error',
      );
    });
  }

  /// Обработка тапа по уведомлению — навигация на конкретный заказ
  // Нажатие на системное FCM-уведомление.
  void _handleNotificationTap(RemoteMessage message) {
    if (!mounted) return;

    final orderId = int.tryParse(
      message.data['order_id']?.toString() ?? '',
    );

    _silentRefresh();

    if (orderId != null) {
      _openOrderDetail(orderId);
    }
  }

// Нажатие на локальное уведомление, показанное сервисом.
  void _handleLocalNotificationTap(int orderId) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _silentRefresh();
      _openOrderDetail(orderId);
    });

    // Запрашиваем кадр, чтобы callback выполнился и при статичном UI.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

// Регистрация текущего токена после входа и при возврате в приложение.
  Future<void> _registerDeviceToken() async {
    try {
      final pushService = PushNotificationService.instance;

      // Firebase.initializeApp() должен быть выполнен ранее в main().
      await pushService.initialize();

      if (!mounted) return;

      await pushService.registerCurrentDeviceToken();

      if (!mounted) return;

      // Приложение могло запуститься через локальное уведомление
      // до появления OrdersScreen.
      final pendingOrderId = pushService.takePendingLocalOrderId();

      if (pendingOrderId != null) {
        _handleLocalNotificationTap(pendingOrderId);
      }
    } catch (e) {
      debugPrint(
        '[OrdersScreen] Ошибка настройки push или регистрации токена: $e',
      );
    }
  }

  /// ✅ "Тихое" обновление — без спиннера на весь экран
  /// Если данные уже есть, показываем маленький индикатор в AppBar
  Future<void> _silentRefresh() async {
    try {
      final orders = await ApiService.getOrders();
      if (!mounted) return;
      setState(() {
        _ordersFuture = Future.value(orders);
      });
    } catch (e) {
      debugPrint('⚠ [OrdersScreen] Silent refresh error: $e');
      // При ошибке ничего не делаем — оставляем старые данные
    }
  }

  /// Ручное обновление (кнопка refresh / pull-to-refresh)
  Future<void> _refresh() async {
    setState(() {
      _ordersFuture = ApiService.getOrders();
    });
    await _ordersFuture;
  }

  Future<void> _openOrderDetail(int orderId) async {
    if (!mounted) return;

    try {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => OrderDetailScreen(orderId: orderId),
        ),
      );

      if (!mounted) return;

      // После возвращения обновляем данные независимо от результата.
      await _silentRefresh();
    } catch (e) {
      debugPrint(
        '[OrdersScreen] Ошибка открытия заказа #$orderId: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallWidth = screenWidth < 400;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Активные заказы',
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: isSmallWidth,
        titleSpacing: isSmallWidth ? 0 : 16,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return FutureBuilder<List<Order>>(
            future: _ordersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return _buildErrorView(snapshot.error.toString());
              }

              final orders = snapshot.data ?? [];

              if (orders.isEmpty) {
                return _buildEmptyView(constraints);
              }

              return RefreshIndicator(
                onRefresh: _refresh,
                child: _buildOrdersList(orders, constraints),
              );
            },
          );
        },
      ),
    );
  }

  /// Отображение списка заказов: на больших экранах карточки центрированы
  /// и ограничены по ширине, на маленьких — во весь экран.
  Widget _buildOrdersList(List<Order> orders, BoxConstraints constraints) {
    final screenWidth = constraints.maxWidth;
    final isWideScreen = screenWidth >= 900;
    final isTablet = screenWidth >= 600 && screenWidth < 900;

    final maxCardWidth = isWideScreen
        ? 600.0
        : isTablet
        ? 520.0
        : double.infinity;

    final horizontalPadding = isWideScreen
        ? 24.0
        : isTablet
        ? 16.0
        : 12.0;

    final listView = ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 12,
      ),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return OrderCard(
          order: order,
          onTap: () => _openOrderDetail(order.id),
        );
      },
    );

    if (isWideScreen || isTablet) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxCardWidth),
          child: listView,
        ),
      );
    }

    return listView;
  }

  Widget _buildErrorView(String errorText) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isVerySmall = screenHeight < 500;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isVerySmall) ...[
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'Ошибка загрузки',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView(BoxConstraints constraints) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isVerySmall = screenHeight < 500;
    final isCompact = screenHeight < 600;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isCompact) ...[
                      Icon(
                        Icons.inbox_rounded,
                        size: isVerySmall ? 48 : 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                    ],
                    const Flexible(
                      child: Text(
                        'Нет активных заказов',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (!isVerySmall) ...[
                      const SizedBox(height: 8),
                      const Flexible(
                        child: Text(
                          'Новые заказы появятся здесь',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Обновить'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// OrderCard — без изменений
// ═══════════════════════════════════════════════════════════════

class OrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;

  const OrderCard({
    Key? key,
    required this.order,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final isVerySmallHeight = size.height < 500;
    final isCompactHeight = size.height < 650;
    final isNarrowWidth = size.width < 360;

    final cardPadding = isVerySmallHeight
        ? 10.0
        : isCompactHeight
        ? 12.0
        : 16.0;

    final sectionSpacing = isVerySmallHeight
        ? 6.0
        : isCompactHeight
        ? 8.0
        : 12.0;

    final titleFontSize = isVerySmallHeight
        ? 15.0
        : isNarrowWidth
        ? 16.0
        : 18.0;

    final iconSize = isVerySmallHeight ? 14.0 : 16.0;
    final bodyFontSize = isVerySmallHeight ? 12.0 : 14.0;
    final smallFontSize = isVerySmallHeight ? 10.0 : 11.0;

    final progressPercent = order.safeProgress;
    final itemsCount = order.safeItemsCount;
    final collectedCount = order.safeCollectedCount;

    return Card(
      margin: EdgeInsets.only(bottom: isVerySmallHeight ? 8 : 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(
                titleFontSize: titleFontSize,
                sectionSpacing: sectionSpacing,
              ),
              SizedBox(height: sectionSpacing),

              if (order.isTimedDelivery) ...[
                _buildInfoRow(
                  icon: Icons.schedule,
                  text: order.isWaitingRelease
                      ? 'Ко времени: ${order.scheduleLabel} · сборка с ${order.releaseLabel}'
                      : 'Доставить: ${order.scheduleLabel}',
                  iconSize: iconSize,
                  fontSize: bodyFontSize,
                  maxLines: 2,
                ),
                SizedBox(height: sectionSpacing / 2),
              ],

              _buildInfoRow(
                icon: Icons.person,
                text: order.customerName,
                iconSize: iconSize,
                fontSize: bodyFontSize,
                maxLines: 1,
              ),
              SizedBox(height: sectionSpacing / 2),

              _buildInfoRow(
                icon: Icons.phone,
                text: order.customerPhone.isNotEmpty
                    ? order.customerPhone
                    : 'Нет номера',
                iconSize: iconSize,
                fontSize: bodyFontSize,
                maxLines: 1,
              ),
              SizedBox(height: sectionSpacing / 2),

              if (order.address.isNotEmpty && !isVerySmallHeight) ...[
                _buildInfoRow(
                  icon: Icons.location_on,
                  text: order.address,
                  iconSize: iconSize,
                  fontSize: bodyFontSize - 1,
                  maxLines: 2,
                ),
                SizedBox(height: sectionSpacing),
              ] else if (order.address.isEmpty)
                SizedBox(height: sectionSpacing / 4),

              _buildProgressRow(
                itemsCount: itemsCount,
                collectedCount: collectedCount,
                fontSize: bodyFontSize,
                sectionSpacing: sectionSpacing,
              ),
              SizedBox(height: sectionSpacing / 2),

              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progressPercent / 100,
                  minHeight: isVerySmallHeight ? 4 : 6,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation(
                    progressPercent >= 100 ? Colors.green : Colors.blue,
                  ),
                ),
              ),
              SizedBox(height: sectionSpacing),

              _buildFooter(
                smallFontSize: smallFontSize,
                bodyFontSize: bodyFontSize,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required double titleFontSize,
    required double sectionSpacing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Заказ #${order.id}',
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _formatDate(order.createdAt),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: _getStatusColor(order.deliveryStatus),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              order.getStatusLabel(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String text,
    required double iconSize,
    required double fontSize,
    required int maxLines,
  }) {
    return Row(
      children: [
        Icon(icon, size: iconSize, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: fontSize),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressRow({
    required int itemsCount,
    required int collectedCount,
    required double fontSize,
    required double sectionSpacing,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            'Товаров: $itemsCount',
            style: TextStyle(fontSize: fontSize),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Собрано: $collectedCount/$itemsCount',
          style: TextStyle(
            fontSize: fontSize,
            color: Colors.green[700],
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter({
    required double smallFontSize,
    required double bodyFontSize,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: _getPaymentColor(order.paymentStatus),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              order.getPaymentStatusLabel(),
              style: TextStyle(
                color: Colors.white,
                fontSize: smallFontSize,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${order.totalPrice.toStringAsFixed(2)} ₽',
            style: TextStyle(
              fontSize: bodyFontSize + 2,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'new':
        return Colors.red;
      case 'scheduled':
        return Colors.teal;
      case 'processing':
        return Colors.orange;
      case 'packed':
        return Colors.blue;
      case 'on_way':
        return Colors.purple;
      case 'delivered':
        return Colors.green;
      case 'canceled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Color _getPaymentColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      case 'refunded':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(dateTime.year, dateTime.month, dateTime.day))
        .inDays;
    if (days == 0) {
      return 'Сегодня ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (days == 1) {
      return 'Вчера ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.day}.${dateTime.month}.${dateTime.year}';
    }
  }
}