import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sborapps/core/services/api_service.dart';
import 'package:sborapps/ui/screens/order_detail_screen.dart';
import 'package:sborapps/ui/screens/orders_screen.dart';

class ScheduledOrdersScreen extends StatefulWidget {
  const ScheduledOrdersScreen({super.key});

  @override
  State<ScheduledOrdersScreen> createState() => _ScheduledOrdersScreenState();
}

class _ScheduledOrdersScreenState extends State<ScheduledOrdersScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  List<Order> _orders = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(silent: true);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final orders = await ApiService.getScheduledOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _orders.isEmpty) _error = e.toString();
      });
    }
  }

  Future<void> _open(Order order) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(orderId: order.id),
      ),
    );
    if (mounted) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: _orders.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                Icon(Icons.schedule, size: 56, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Заказов ко времени нет',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: _orders.length,
              itemBuilder: (context, index) {
                final order = _orders[index];
                return OrderCard(
                  order: order,
                  onTap: () => _open(order),
                );
              },
            ),
    );
  }
}
