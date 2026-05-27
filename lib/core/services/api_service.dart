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

  // ✅ Единый обработчик ответа — больше не дублируем код в каждом методе
  static void _checkResponse(http.Response response) async {
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

  /// Получить активные заказы для сборщика
  static Future<List<Order>> getOrders() async {
    try {
      final headers = await _buildHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/orders_api.php?action=get_orders'),
        headers: headers,
      ).timeout(_timeout);

      _checkResponse(response);

      final data = jsonDecode(response.body);
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

  /// Получить детали заказа со всеми товарами
  static Future<Order> getOrderDetail(int orderId) async {
    try {
      final headers = await _buildHeaders();
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/orders_api.php?action=get_order_detail&order_id=$orderId',
        ),
        headers: headers,
      ).timeout(_timeout);

      _checkResponse(response);

      final json = jsonDecode(response.body);
      return Order.fromJson(json as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Нет соединения с сервером: $e');
    }
  }

  /// Обновить статус заказа
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

      _checkResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Нет соединения с сервером: $e');
    }
  }

  /// Обновить статус отдельного товара в заказе
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

      _checkResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Нет соединения с сервером: $e');
    }
  }

  /// Получить историю заказов
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

      _checkResponse(response);

      final data = jsonDecode(response.body);
      return HistoryResponse.fromJson(data as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Нет соединения с сервером: $e');
    }
  }

  /// Получить статистику по заказам
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

      _checkResponse(response);

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

class Order {
  final int id;
  final String customerName;
  final String customerPhone;
  final double totalPrice;
  final double bonusSpent;
  final double bonusEarned;
  final String deliveryStatus;
  final String paymentStatus;
  final String address;
  final List<OrderItem> items;
  final DateTime createdAt;
  final int? itemsCount;
  final int? collectedCount;
  final int? progress;

  const Order({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.totalPrice,
    this.bonusSpent = 0,
    this.bonusEarned = 0,
    required this.deliveryStatus,
    required this.paymentStatus,
    required this.address,
    this.items = const [],
    required this.createdAt,
    this.itemsCount,
    this.collectedCount,
    this.progress,
  });

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
    );
  }

  // Геттер для совместимости если где-то используется order.status
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
    String? address,
    List<OrderItem>? items,
    DateTime? createdAt,
    int? itemsCount,
    int? collectedCount,
    int? progress,
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
      address: address ?? this.address,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      itemsCount: itemsCount ?? this.itemsCount,
      collectedCount: collectedCount ?? this.collectedCount,
      progress: progress ?? this.progress,
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

  const OrderItem({
    this.id = 0,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    this.isCollected = false,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] ?? 0,
      productId: json['product_id'] ?? '',
      productName: json['product_name'] ?? '',
      quantity: json['quantity'] ?? 0,
      price: _parseDouble(json['price']),
      isCollected: json['is_collected'] ?? false,
    );
  }

  OrderItem copyWith({
    int? id,
    String? productId,
    String? productName,
    int? quantity,
    double? price,
    bool? isCollected,
  }) {
    return OrderItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      isCollected: isCollected ?? this.isCollected,
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