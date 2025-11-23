import 'package:flutter/material.dart';
import '../../models/order.dart';

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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          order.customerName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📞 ${order.customerPhone}'),
            Text('📦 ${order.items.length} товаров'),
            Text('💰 ${order.totalPrice}'),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: order.status == 'completed' ? Colors.green : Colors.orange,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            order.status == 'completed' ? 'Готов' : 'Новый',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
