class Order {
  final int id;
  final String customerName;
  final String customerPhone;
  final List<OrderItem> items;
  final String status;
  final double totalPrice;
  final DateTime createdAt;

  Order({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.status,
    required this.totalPrice,
    required this.createdAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] ?? 0,
      customerName: json['customer_name'] ?? 'Неизвестный',
      customerPhone: json['customer_phone'] ?? '',
      items: (json['items'] as List? ?? [])
          .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      status: json['delivery_status'] ?? json['status'] ?? 'new',
      totalPrice: (json['total_price'] is String)
          ? double.tryParse(json['total_price']) ?? 0
          : (json['total_price'] ?? 0).toDouble(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Order copyWith({
    int? id,
    String? customerName,
    String? customerPhone,
    List<OrderItem>? items,
    String? status,
    double? totalPrice,
    DateTime? createdAt,
  }) {
    return Order(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      items: items ?? this.items,
      status: status ?? this.status,
      totalPrice: totalPrice ?? this.totalPrice,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class OrderItem {
  final int id;
  final String productId;
  final String productName;
  final int quantity;
  final double price;
  final bool isCollected;

  OrderItem({
    required this.id,
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
      price: (json['price'] is String)
          ? double.tryParse(json['price']) ?? 0
          : (json['price'] ?? 0).toDouble(),
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