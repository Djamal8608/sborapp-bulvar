import 'package:flutter/material.dart';
import 'package:sborapps/core/services/api_service.dart';
import 'package:sborapps/core/order_state_provider.dart';
import 'package:sborapps/ui/screens/scanner_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final int orderId;

  const OrderDetailScreen({
    Key? key,
    required this.orderId,
  }) : super(key: key);

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Order? _order;
  List<OrderItem> _items = [];
  bool _isLoading = false;
  bool _isInitialLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    final isInitialLoad = _order == null;

    try {
      final order = await ApiService.getOrderDetail(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _items = List<OrderItem>.from(order.items);
        _isInitialLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (isInitialLoad) {
        setState(() {
          _isInitialLoading = false;
          _loadError = e.toString();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось обновить: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _updateItemStatus(OrderItem item, bool value) async {
    if (_order == null) return;

    await instance.saveState(CollectedState(
      orderId: _order!.id,
      itemId: item.id,
      isCollected: value,
    ));

    final index = _items.indexWhere((e) => e.id == item.id);
    if (index == -1) return;

    setState(() {
      _items[index] = _items[index].copyWith(isCollected: value);
    });

    try {
      await ApiService.updateItemStatus(_order!.id, item.id, value);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value ? '✓ ${item.productName} собран' : '✗ ${item.productName} убран',
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items[index] = _items[index].copyWith(isCollected: !value);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openScanner() async {
    if (_order == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          title: 'Сборка заказа #${_order!.id}',
          onScan: _handleScan,
        ),
      ),
    );

    if (!mounted) return;
    await _loadOrder();
  }

  Future<ScanFeedback> _handleScan(String barcode) async {
    final order = _order;
    if (order == null) {
      return const ScanFeedback(ok: false, text: 'Заказ не загружен');
    }

    final result = await ApiService.scanItem(order.id, barcode);

    if (!result.found) {
      final text = result.reason == 'unknown_barcode'
          ? 'Штрихкод не найден в каталоге'
          : 'Не из этого заказа${result.productName.isNotEmpty ? ': ${result.productName}' : ''}';
      return ScanFeedback(ok: false, text: text);
    }

    if (result.itemId != null && mounted) {
      final index = _items.indexWhere((e) => e.id == result.itemId);
      if (index != -1) {
        setState(() {
          _items[index] = _items[index].copyWith(isCollected: true);
        });
      }
    }

    final suffix = ' — собрано ${result.collectedCount} из ${result.itemsCount}';

    if (result.already) {
      return ScanFeedback(
        ok: true,
        text: 'Уже отмечено: ${result.productName}$suffix',
      );
    }

    return ScanFeedback(
      ok: true,
      text: '${result.productName}$suffix',
    );
  }

  static const Set<String> _beforePicking = {'new', 'paid', 'receipt_created'};

  Future<void> _startPicking() async {
    final order = _order;
    if (order == null) return;

    setState(() => _isLoading = true);

    try {
      await ApiService.updateOrderStatus(order.id, 'processing');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сборка начата'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      await _loadOrder();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _prepareOrder() async {
    if (_order == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отправить на доставку?'),
        content: const Text(
          'Заказ будет отмечен как готов к доставке.\n'
              'Доставщик сможет забрать посылку.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await ApiService.updateOrderStatus(_order!.id, 'packed');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Заказ готов к доставке!'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      await _loadOrder();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _completeOrder() async {
    if (_order == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Завершить сборку?'),
        content: Text(
          'Заказ #${_order!.id} будет отмечен как упакованный.\n'
              'Собрано товаров: ${_items.length} из ${_items.length}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await ApiService.updateOrderStatus(_order!.id, 'packed');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Заказ успешно завершён!'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Заказ #${widget.orderId}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _order != null ? _openScanner : null,
            tooltip: 'Сканировать',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrder,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return _buildErrorWidget(_loadError!);
    }

    final order = _order;
    if (order == null) {
      return const Center(child: Text('Заказ не найден'));
    }

    final collectedCount = _items.where((e) => e.isCollected).length;
    final totalCount = _items.length;
    final allCollected = totalCount > 0 && collectedCount == totalCount;
    final progressValue = totalCount > 0 ? collectedCount / totalCount : 0.0;

    return Column(
      children: [
        _buildOrderInfoCard(collectedCount, totalCount, progressValue),
        Expanded(child: _buildItemsList()),
        _buildCompleteButton(allCollected),
      ],
    );
  }

  Widget _buildPaymentBanner() {
    final order = _order;
    if (order == null) return const SizedBox.shrink();

    final MaterialColor color;
    final IconData icon;

    switch (order.paymentState) {
      case 'paid_online':
        color = Colors.green;
        icon = Icons.verified;
        break;
      case 'awaiting_payment':
        color = Colors.red;
        icon = Icons.hourglass_empty;
        break;
      default:
        color = Colors.orange;
        icon = Icons.payments_outlined;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.shade800, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  order.paymentLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: color.shade800,
                  ),
                ),
                Text(
                  order.paymentHint,
                  style: TextStyle(fontSize: 13, color: color.shade800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Ошибка загрузки',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadOrder,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderInfoCard(
      int collectedCount,
      int totalCount,
      double progressValue,
      ) {
    if (_order == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPaymentBanner(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Имя и телефон
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _order!.customerName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.phone, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            _order!.customerPhone.isNotEmpty
                                ? _order!.customerPhone
                                : 'Нет номера',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Цена
                Text(
                  '${_order!.totalPrice.toStringAsFixed(2)} ₽',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            if (_order!.address.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _order!.address,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            // Прогресс сборки
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Собрано: $collectedCount из $totalCount',
                  style: const TextStyle(fontSize: 13),
                ),
                Text(
                  '${(progressValue * 100).round()}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: progressValue == 1.0 ? Colors.green : Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progressValue,
                minHeight: 8,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation(
                  progressValue == 1.0 ? Colors.green : Colors.blue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsList() {
    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('В заказе нет товаров'),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _items[index];

        return CheckboxListTile(
          // ✅ value берётся из локального _items, не из order.items
          value: item.isCollected,
          onChanged: (value) => _updateItemStatus(item, value ?? false),
          title: Text(
            item.productName,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              decoration: item.isCollected
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
              color: item.isCollected ? Colors.grey : null,
            ),
          ),
          subtitle: Text(
            '× ${item.quantity}  •  ${item.price.toStringAsFixed(2)} ₽',
            style: const TextStyle(fontSize: 12),
          ),
          secondary: CircleAvatar(
            radius: 16,
            backgroundColor:
            item.isCollected ? Colors.green[100] : Colors.grey[200],
            child: Text(
              '${item.quantity}',
              style: TextStyle(
                fontSize: 12,
                color: item.isCollected ? Colors.green[800] : Colors.grey[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          activeColor: Colors.green,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        );
      },
    );
  }

  Widget _buildCompleteButton(bool allCollected) {
    final status = _order?.status ?? 'new';

    final String label;
    final IconData icon;
    final VoidCallback? action;
    final Color? color;

    if (_beforePicking.contains(status)) {
      label = 'Начать сборку';
      icon = Icons.play_arrow;
      action = _isLoading ? null : _startPicking;
      color = Colors.blue;
    } else if (status == 'processing') {
      label = allCollected ? 'Готов к доставке' : 'Собрать все товары';
      icon = allCollected ? Icons.local_shipping : Icons.pending_actions;
      action = (allCollected && !_isLoading) ? _prepareOrder : null;
      color = allCollected ? Colors.green : null;
    } else {
      label = 'Заказ отправлен';
      icon = Icons.check_circle;
      action = null;
      color = null;
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton(
        onPressed: action,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}