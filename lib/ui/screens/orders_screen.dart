import 'package:flutter/material.dart';
import '../../core/services/php_service.dart';
import '../../models/order.dart';
import '../widgets/order_card.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final orders = PhpService.getMockOrders()
        .where((order) => order.status == 'new')
        .toList();

    return orders.isEmpty
        ? const Center(child: Text('Нет новых заказов'))
        : ListView.builder(
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return OrderCard(
          order: order,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OrderDetailScreen(order: order),
            ),
          ),
        );
      },
    );
  }
}
