import 'package:flutter/material.dart';
import 'package:sborapps/core/services/api_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final List<Order> _orders = [];
  final ScrollController _scrollController = ScrollController();

  static const int _limit = 20;
  int _offset = 0;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isInitialLoad = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadOrders() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await ApiService.getOrderHistory(
        limit: _limit,
        offset: _offset,
      );

      if (!mounted) return;
      setState(() {
        _orders.addAll(response.orders);
        _offset += response.orders.length;
        _hasMore = response.orders.length >= _limit;
        _isLoading = false;
        _isInitialLoad = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _isInitialLoad = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    await _loadOrders();
  }

  Future<void> _refresh() async {
    setState(() {
      _orders.clear();
      _offset = 0;
      _hasMore = true;
      _isInitialLoad = true;
      _error = null;
    });
    await _loadOrders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История заказов'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Первичная загрузка
    if (_isInitialLoad && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Ошибка при первичной загрузке
    if (_error != null && _orders.isEmpty) {
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
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    // Пустой список
    if (_orders.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'История пуста',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Завершённые заказы появятся здесь',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Обновить'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        // +1 для индикатора загрузки внизу или сообщения "всё загружено"
        itemCount: _orders.length + 1,
        itemBuilder: (context, index) {
          // Последний элемент — индикатор загрузки или конец списка
          if (index == _orders.length) {
            if (_isLoading) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (!_hasMore && _orders.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Показано все ${_orders.length} заказов',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }

          // Ошибка при подгрузке следующей страницы
          if (_error != null && index == _orders.length - 1) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      'Ошибка загрузки: $_error',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            );
          }

          return HistoryOrderCard(
            key: ValueKey(_orders[index].id),
            order: _orders[index],
          );
        },
      ),
    );
  }
}

class HistoryOrderCard extends StatefulWidget {
  final Order order;

  const HistoryOrderCard({Key? key, required this.order}) : super(key: key);

  @override
  State<HistoryOrderCard> createState() => _HistoryOrderCardState();
}

class _HistoryOrderCardState extends State<HistoryOrderCard> {
  bool _expanded = false;
  Future<Order>? _details;

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      _details ??= ApiService.getOrderDetail(widget.order.id);
    });
  }

  void _reload() {
    setState(() {
      _details = ApiService.getOrderDetail(widget.order.id);
    });
  }

  Widget _buildItems() {
    return FutureBuilder<Order>(
      future: _details,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Row(
            children: [
              Expanded(
                child: Text(
                  'Не удалось загрузить состав заказа',
                  style: TextStyle(fontSize: 13, color: Colors.red[700]),
                ),
              ),
              TextButton(
                onPressed: _reload,
                child: const Text('Повторить'),
              ),
            ],
          );
        }

        final details = snapshot.data!;
        final items = details.items;
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'В заказе нет позиций',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          );
        }

        final reduced = details.originalTotalPrice - details.totalPrice;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _buildItemRow(items[i]),
            ],
            if (reduced > 0.009) ...[
              const SizedBox(height: 8),
              Text(
                'Сумма уменьшена на ${reduced.toStringAsFixed(2)} ₽: '
                    'было ${details.originalTotalPrice.toStringAsFixed(2)} ₽',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange[800],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildItemRow(OrderItem item) {
    final missing = item.isUnavailable;
    final partial = item.isPartial;
    final picked = item
        .quantityText(item.pickedQuantity)
        .replaceAll(RegExp(r' (шт|кг)$'), '');

    final String quantity;
    final Color quantityColor;
    if (missing) {
      quantity = 'нет в наличии';
      quantityColor = Colors.red[700]!;
    } else if (partial) {
      quantity = '$picked из ${item.quantityText(item.quantity)}';
      quantityColor = Colors.orange[800]!;
    } else {
      quantity = item.quantityText(item.quantity);
      quantityColor = Colors.grey[700]!;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: TextStyle(
                    fontSize: 13,
                    color: missing ? Colors.grey : null,
                    decoration: missing
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  quantity,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: (missing || partial)
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: quantityColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            missing ? '—' : '${item.subtotal.toStringAsFixed(2)} ₽',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isDelivered = order.deliveryStatus == 'delivered';
    final isCanceled = order.deliveryStatus == 'canceled';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          // ✅ Визуальный акцент по статусу
          color: isDelivered
              ? Colors.green.withOpacity(0.3)
              : isCanceled
              ? Colors.red.withOpacity(0.3)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Заказ #${order.id}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(order.createdAt),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDelivered
                        ? Colors.green
                        : isCanceled
                        ? Colors.red
                        : Colors.grey,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    order.getStatusLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Клиент
            Row(
              children: [
                const Icon(Icons.person, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.customerName,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Телефон
            Row(
              children: [
                const Icon(Icons.phone, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  order.customerPhone.isNotEmpty
                      ? order.customerPhone
                      : 'Нет номера',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),

            // Адрес если есть
            if (order.address.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.address,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Итог
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.shopping_bag_outlined,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      // ✅ safeItemsCount — без null
                      '${order.safeItemsCount} товаров',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Статус оплаты
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _getPaymentColor(order.paymentStatus),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        order.getPaymentStatusLabel(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${order.totalPrice.toStringAsFixed(2)} ₽',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.list_alt, size: 18, color: Colors.blue[700]),
                    const SizedBox(width: 6),
                    Text(
                      _expanded ? 'Скрыть состав' : 'Состав заказа',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[700],
                      ),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more, color: Colors.blue[700]),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) _buildItems(),
          ],
        ),
      ),
    );
  }

  Color _getPaymentColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      case 'refunded':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(dateTime.year, dateTime.month, dateTime.day))
        .inDays;
    final time =
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';

    if (days == 0) {
      return 'Сегодня $time';
    } else if (days == 1) {
      return 'Вчера $time';
    } else {
      return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} $time';
    }
  }
}