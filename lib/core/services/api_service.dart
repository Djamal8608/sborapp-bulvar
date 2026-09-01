import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sborapps/core/services/admin_auth_service.dart';

double _parseDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

class ApiService {
  static const String _baseUrl = 'https://dagix.ru/BrBulvar/sbor_api';
  static const Duration _timeout = Duration(seconds: 30);

  static Future<Map<String, String>> _buildHeaders() async {
    final token = await AdminAuthService.getToken();
    return {
      'Content-Type': 'application/json; charset=utf-8',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Future<void>, а не void: у `void ... async` бросок улетает в отдельный
  // микротаск — try/catch вызывающего его не ловит, и код идёт дальше
  // парсить пустое тело ответа.
  static Future<void> _checkResponse(http.Response response) async {
    if (response.statusCode == 401) {
      await AdminAuthService.logout();
      throw ApiException('Сессия истекла, требуется переавторизация', 401);
    }
    if (response.statusCode != 200) {
      String message = 'Ошибка сервера (${response.statusCode})';
      try {
        final error = jsonDecode(response.body);
        if (error['error'] != null) message = error['error'];
      } catch (_) {}
      throw ApiException(message, response.statusCode);
    }
  }

  static Future<List<Order>> getOrders() async {
    try {
      final headers = await _buildHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/orders_api.php?action=get_orders'),
        headers: headers,
      ).timeout(_timeout);

      await _checkResponse(response);

      final data = jsonDecode(response.body);
      if (data is Map && data['delivery_gateway_sent'] == false) {
        throw ApiException('Заказ упакован, но шлюз доставки его не принял');
      }
      final List ordersJson = data['orders'] ?? [];
      return ordersJson
          .map((json) => Order.fromJson(json as Map<String, dynamic>))
          .toList();
    } on ApiException {
      rethrow; // ✅ ApiException пробрасываем как есть
    } catch (e) {
      throw ApiException('Нет соединения с сервером: $e');
    }
  }

  static Future<Order> getOrderDetail(int orderId) async {
    try {
      final headers = await _buildHeaders();
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/orders_api.php?action=get_order_detail&order_id=$orderId',
        ),
        headers: headers,
      ).timeout(_timeout);

      await _checkResponse(response);

      final json = jsonDecode(response.body);
      return Order.fromJson(json as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Нет соединения с сервером: $e');
    }
  }

  static Future<void> updateOrderStatus(int orderId, String status) async {
    try {
      final headers = await _buildHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/orders_api.php?action=update_order_status'),
        headers: headers,
        body: jsonEncode({
          'order_id': orderId,
          'status': status,
        }),
      ).timeout(_timeout);

      await _checkResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Нет соединения с сервером: $e');
    }
  }

  static Future<void> updateItemStatus(
      int orderId,
      int itemId,
      bool isCollected,
      ) async {
    try {
      final headers = await _buildHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/orders_api.php?action=update_item_status'),
        headers: headers,
        body: jsonEncode({
          'order_id': orderId,
          'item_id': itemId,
          'is_collected': isCollected,
        }),
      ).timeout(_timeout);

      await _checkResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Нет соединения с сервером: $e');
    }
  }

  /// Отметить позицию как отсутствующую в магазине (или вернуть её в заказ).
  /// Сервер сам пересчитывает сумму заказа и возвращает новые итоги.
  static Future<OrderAmounts> setItemUnavailable(
      int orderId,
      int itemId,
      bool isUnavailable,
      ) async {
    try {
      final headers = await _buildHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/orders_api.php?action=set_item_unavailable'),
        headers: headers,
        body: jsonEncode({
          'order_id': orderId,
          'item_id': itemId,
          'is_unavailable': isUnavailable,
        }),
      ).timeout(_timeout);

      await _checkResponse(response);

      return OrderAmounts.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Нет соединения с сервером: $e');
    }
  }

  static Future<ScanResult> scanItem(int orderId, String barcode) async {
    try {
      final headers = await _buildHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/orders_api.php?action=scan_item'),
        headers: headers,
        body: jsonEncode({
          'order_id': orderId,
          'barcode': barcode,
        }),
      ).timeout(_timeout);

      await _checkResponse(response);

      return ScanResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Нет соединения с сервером: $e');
    }
  }

  static Future<HistoryResponse> getOrderHistory({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final headers = await _buildHeaders();
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/orders_api.php?action=get_history&limit=$limit&offset=$offset',
        ),
        headers: headers,
      ).timeout(_timeout);

      await _checkResponse(response);

      final data = jsonDecode(response.body);
      return HistoryResponse.fromJson(data as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Нет соединения с сервером: $e');
    }
  }

  static Future<Statistics> getStatistics({
    String period = 'today',
  }) async {
    try {
      final headers = await _buildHeaders();
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/orders_api.php?action=get_statistics&period=$period',
        ),
        headers: headers,
      ).timeout(_timeout);

      await _checkResponse(response);

      final json = jsonDecode(response.body);
      return Statistics.fromJson(json as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Нет соединения с сервером: $e');
    }
  }
}

// ============================================
// Exception
// ============================================

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() =>
      'ApiException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
}

// ============================================
// Models
// ============================================

/// Итоги по деньгам заказа после изменения состава.
class OrderAmounts {
  /// Актуальная сумма — её берут с клиента при оплате курьеру.
  final double totalPrice;

  /// Сумма при оформлении. Именно её списала ЮKassa.
  final double originalTotalPrice;

  /// Сколько стоили позиции, которых не оказалось в наличии.
  final double removedTotal;

  /// К возврату. Ненулевой только для заказов, оплаченных онлайн.
  /// Возврат пока оформляется вручную — автоматики нет.
  final double refundDue;

  final int unavailableCount;

  const OrderAmounts({
    this.totalPrice = 0,
    this.originalTotalPrice = 0,
    this.removedTotal = 0,
    this.refundDue = 0,
    this.unavailableCount = 0,
  });

  factory OrderAmounts.fromJson(Map<String, dynamic> json) {
    return OrderAmounts(
      totalPrice: _parseDouble(json['total_price']),
      originalTotalPrice: _parseDouble(json['original_total_price']),
      removedTotal: _parseDouble(json['removed_total']),
      refundDue: _parseDouble(json['refund_due']),
      unavailableCount: json['unavailable_count'] is int
          ? json['unavailable_count'] as int
          : 0,
    );
  }
}

class ScanResult {

  final bool found;

  final bool already;

  final String reason;

  final String message;
  final String productName;
  final int? itemId;
  final int itemsCount;
  final int collectedCount;
  final int progress;

  const ScanResult({
    required this.found,
    required this.already,
    required this.reason,
    required this.message,
    required this.productName,
    required this.itemId,
    required this.itemsCount,
    required this.collectedCount,
    required this.progress,
  });

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    return ScanResult(
      found: json['found'] == true,
      already: json['already'] == true,
      reason: json['reason']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? '',
      itemId: json['item_id'] is int ? json['item_id'] as int : null,
      itemsCount: json['items_count'] is int ? json['items_count'] as int : 0,
      collectedCount:
      json['collected_count'] is int ? json['collected_count'] as int : 0,
      progress: json['progress'] is int ? json['progress'] as int : 0,
    );
  }
}

class Order {
  final int id;
  final String customerName;
  final String customerPhone;
  final double totalPrice;
  final double bonusSpent;
  final double bonusEarned;
  final String deliveryStatus;
  final String paymentStatus;
  final String paymentMethod;
  final bool isPaidOnline;
  final String _paymentState;
  final String address;
  final List<OrderItem> items;
  final DateTime createdAt;
  final int? itemsCount;
  final int? collectedCount;
  final int? progress;

  /// Сумма заказа при оформлении — до того, как сборщик снял
  /// отсутствующие позиции. Её списала ЮKassa.
  final double originalTotalPrice;

  /// Стоимость снятых позиций.
  final double removedTotal;

  /// К возврату клиенту (только для оплаченных онлайн).
  final double refundDue;

  final int unavailableCount;

  const Order({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.totalPrice,
    this.bonusSpent = 0,
    this.bonusEarned = 0,
    required this.deliveryStatus,
    required this.paymentStatus,
    this.paymentMethod = 'cash',
    this.isPaidOnline = false,
    String paymentState = 'on_delivery',
    required this.address,
    this.items = const [],
    required this.createdAt,
    this.itemsCount,
    this.collectedCount,
    this.progress,
    double? originalTotalPrice,
    this.removedTotal = 0,
    this.refundDue = 0,
    this.unavailableCount = 0,
  })  : _paymentState = paymentState,
        originalTotalPrice = originalTotalPrice ?? totalPrice;

  String get paymentState => _paymentState;

  bool get isAwaitingPayment => _paymentState == 'awaiting_payment';

  String get paymentLabel {
    switch (_paymentState) {
      case 'paid_online':
        return 'Оплачен онлайн';
      case 'awaiting_payment':
        return 'Ожидает оплаты';
      default:
        return 'Оплата при получении';
    }
  }

  String get paymentHint {
    switch (_paymentState) {
      case 'paid_online':
        return 'Деньги с клиента не брать';
      case 'awaiting_payment':
        return 'Оплата ещё не подтверждена — не выдавать';
      default:
        return 'Взять с клиента ₽${totalPrice.toStringAsFixed(2)}';
    }
  }

  double get amountToCollect => isPaidOnline ? 0 : totalPrice;

  /// Состав заказа изменился: что-то не нашлось на полке.
  bool get hasUnavailable => removedTotal > 0 || unavailableCount > 0;

  factory Order.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? [];
    return Order(
      id: json['id'] ?? 0,
      customerName: json['customer_name'] ?? 'Неизвестный',
      customerPhone: json['customer_phone'] ?? '',
      totalPrice: _parseDouble(json['total_price']),
      bonusSpent: _parseDouble(json['bonus_spent']),
      bonusEarned: _parseDouble(json['bonus_earned']),
      deliveryStatus: json['delivery_status'] ?? 'new',
      paymentStatus: json['payment_status'] ?? 'pending',
      paymentMethod: json['payment_method']?.toString() ?? 'cash',
      isPaidOnline: json['is_paid_online'] == true,
      paymentState: json['payment_state']?.toString() ?? 'on_delivery',
      address: json['address'] ?? '',
      items: rawItems
          .map((x) => OrderItem.fromJson(x as Map<String, dynamic>))
          .toList(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      itemsCount: json['items_count'],
      collectedCount: json['collected_count'],
      progress: json['progress'],
      originalTotalPrice: json['original_total_price'] != null
          ? _parseDouble(json['original_total_price'])
          : null,
      removedTotal: _parseDouble(json['removed_total']),
      refundDue: _parseDouble(json['refund_due']),
      unavailableCount: json['unavailable_count'] is int
          ? json['unavailable_count'] as int
          : 0,
    );
  }

  String get status => deliveryStatus;

  // ✅ Безопасные геттеры без null
  int get safeItemsCount => itemsCount ?? items.length;

  int get safeCollectedCount =>
      collectedCount ?? items.where((e) => e.isCollected).length;

  // ✅ Добавлен safeProgress — нужен в OrderCard и HistoryOrderCard
  int get safeProgress =>
      progress ??
          (safeItemsCount > 0
              ? ((safeCollectedCount / safeItemsCount) * 100).round()
              : 0);

  Order copyWith({
    int? id,
    String? customerName,
    String? customerPhone,
    double? totalPrice,
    double? bonusSpent,
    double? bonusEarned,
    String? deliveryStatus,
    String? paymentStatus,
    String? paymentMethod,
    bool? isPaidOnline,
    String? address,
    List<OrderItem>? items,
    DateTime? createdAt,
    int? itemsCount,
    int? collectedCount,
    int? progress,
    double? originalTotalPrice,
    double? removedTotal,
    double? refundDue,
    int? unavailableCount,
  }) {
    return Order(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      totalPrice: totalPrice ?? this.totalPrice,
      bonusSpent: bonusSpent ?? this.bonusSpent,
      bonusEarned: bonusEarned ?? this.bonusEarned,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isPaidOnline: isPaidOnline ?? this.isPaidOnline,
      paymentState: _paymentState,
      address: address ?? this.address,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      itemsCount: itemsCount ?? this.itemsCount,
      collectedCount: collectedCount ?? this.collectedCount,
      progress: progress ?? this.progress,
      originalTotalPrice: originalTotalPrice ?? this.originalTotalPrice,
      removedTotal: removedTotal ?? this.removedTotal,
      refundDue: refundDue ?? this.refundDue,
      unavailableCount: unavailableCount ?? this.unavailableCount,
    );
  }

  String getStatusLabel() {
    const statuses = {
      'new': 'Новый',
      'processing': 'Обработка',
      'packed': 'Упакован',
      'on_way': 'В пути',
      'delivered': 'Доставлен',
      'canceled': 'Отменен',
    };
    return statuses[deliveryStatus] ?? deliveryStatus;
  }

  String getPaymentStatusLabel() {
    const statuses = {
      'pending': 'Ожидание',
      'paid': 'Оплачено',
      'failed': 'Ошибка',
      'refunded': 'Возврат',
    };
    return statuses[paymentStatus] ?? paymentStatus;
  }
}

class OrderItem {
  final int id;
  final String productId;
  final String productName;
  final int quantity;
  final double price;
  final bool isCollected;

  /// Товара не оказалось в магазине. Позиция исключена из суммы заказа.
  final bool isUnavailable;

  const OrderItem({
    this.id = 0,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    this.isCollected = false,
    this.isUnavailable = false,
  });

  double get subtotal => price * quantity;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] ?? 0,
      productId: json['product_id'] ?? '',
      productName: json['product_name'] ?? '',
      quantity: json['quantity'] ?? 0,
      price: _parseDouble(json['price']),
      isCollected: json['is_collected'] ?? false,
      isUnavailable: json['is_unavailable'] ?? false,
    );
  }

  OrderItem copyWith({
    int? id,
    String? productId,
    String? productName,
    int? quantity,
    double? price,
    bool? isCollected,
    bool? isUnavailable,
  }) {
    return OrderItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      isCollected: isCollected ?? this.isCollected,
      isUnavailable: isUnavailable ?? this.isUnavailable,
    );
  }
}

class HistoryResponse {
  final List<Order> orders;
  final int total;
  final int limit;
  final int offset;

  const HistoryResponse({
    required this.orders,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory HistoryResponse.fromJson(Map<String, dynamic> json) {
    final rawOrders = json['orders'] as List? ?? [];
    return HistoryResponse(
      orders: rawOrders
          .map((x) => Order.fromJson(x as Map<String, dynamic>))
          .toList(),
      total: json['total'] ?? 0,
      limit: json['limit'] ?? 50,
      offset: json['offset'] ?? 0,
    );
  }
}

class Statistics {
  final int totalOrders;
  final int completedOrders;
  final double totalAmount;
  final double averageOrder;
  final int itemsCollected;

  const Statistics({
    required this.totalOrders,
    required this.completedOrders,
    required this.totalAmount,
    required this.averageOrder,
    this.itemsCollected = 0,
  });

  factory Statistics.fromJson(Map<String, dynamic> json) {
    return Statistics(
      totalOrders: json['total_orders'] ?? 0,
      completedOrders: json['completed_orders'] ?? 0,
      totalAmount: _parseDouble(json['total_amount']),
      averageOrder: _parseDouble(json['average_order']),
      itemsCollected: json['items_collected'] ?? 0,
    );
  }
}