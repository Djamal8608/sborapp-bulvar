import 'package:flutter/material.dart';
import '../../core/services/php_service.dart';
import '../../models/order.dart';
import '../widgets/order_card.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final orders = PhpService.getMockOrders()
        .where((order) => order.status == 'completed')
        .toList();

    return orders.isEmpty
        ? const Center(child: Text('История пуста'))
        : ListView.builder(
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return OrderCard(order: order, onTap: () {});
      },
    );
  }
}
