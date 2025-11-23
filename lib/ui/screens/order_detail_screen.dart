import 'package:flutter/material.dart';
import '../../models/order.dart';

class OrderDetailScreen extends StatefulWidget {
  final Order order;

  const OrderDetailScreen({Key? key, required this.order}) : super(key: key);

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late List<OrderItem> items;

  @override
  void initState() {
    super.initState();
    items = List.from(widget.order.items);
  }

  @override
  Widget build(BuildContext context) {
    final allCollected = items.every((item) => item.isCollected);

    return Scaffold(
      appBar: AppBar(title: Text('Заказ #${widget.order.id}')),
      body: Column(
        children: [
          Card(
            child: ListTile(
              title: Text(widget.order.customerName),
              subtitle: Text('📞 ${widget.order.customerPhone}'),
              trailing: Text(widget.order.totalPrice),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return CheckboxListTile(
                  title: Text('${item.name} × ${item.quantity}'),
                  value: item.isCollected,
                  onChanged: (value) {
                    setState(() {
                      items[index] = OrderItem(
                        name: item.name,
                        quantity: item.quantity,
                        isCollected: value ?? false,
                      );
                    });
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: allCollected ? _completeOrder : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: Text(allCollected ? 'Завершить сборку' : 'Собрать все товары'),
            ),
          ),
        ],
      ),
    );
  }

  void _completeOrder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Заказ завершен!')),
    );
    Navigator.pop(context);
  }
}
