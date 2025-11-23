class Order {
  final String id;
  final String customerName;
  final String customerPhone;
  final List<OrderItem> items;
  final String status;
  final String totalPrice;
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
}

class OrderItem {
  final String name;
  final int quantity;
  final bool isCollected;

  OrderItem({
    required this.name,
    required this.quantity,
    this.isCollected = false,
  });
}
