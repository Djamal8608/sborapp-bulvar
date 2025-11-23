import '../../models/order.dart';

class PhpService {
  // Заглушка для будущего API
  static List<Order> getMockOrders() {
    return [
      Order(
        id: '1',
        customerName: 'Иван Иванов',
        customerPhone: '+7 999 123-45-67',
        items: [
          OrderItem(name: 'Хлеб белый', quantity: 2),
          OrderItem(name: 'Молоко 2л', quantity: 1),
        ],
        status: 'new',
        totalPrice: '450 ₽',
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
      Order(
        id: '2',
        customerName: 'Елена Петрова',
        customerPhone: '+7 999 987-65-43',
        items: [
          OrderItem(name: 'Яблоки 1кг', quantity: 1, isCollected: true),
          OrderItem(name: 'Бананы', quantity: 3, isCollected: true),
        ],
        status: 'completed',
        totalPrice: '320 ₽',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      Order(
        id: '3',
        customerName: 'Владимир Сидоров',
        customerPhone: '+7 999 555-44-33',
        items: [
          OrderItem(name: 'Картофель 2кг', quantity: 1),
          OrderItem(name: 'Сметана 20%', quantity: 2),
        ],
        status: 'new',
        totalPrice: '280 ₽',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    ];
  }
}
