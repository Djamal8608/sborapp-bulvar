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

  /// Отметить, что товара нет в магазине (или вернуть его в заказ).
  /// Сумма заказа пересчитывается на сервере — берём её из ответа.
  Future<void> _setUnavailable(OrderItem item, bool value) async {
    final order = _order;
    if (order == null) return;

    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Товара нет в наличии?'),
          content: Text(
            '«${item.productName}» будет исключён из заказа.\n\n'
                'Сумма уменьшится на ${item.subtotal.toStringAsFixed(2)} ₽, '
                'клиент увидит это в своём приложении.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Нет в наличии'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    final index = _items.indexWhere((e) => e.id == item.id);
    if (index == -1) return;

    final previous = _items[index];

    setState(() {
      // Отсутствующий товар не может считаться собранным.
      _items[index] = previous.copyWith(
        isUnavailable: value,
        isCollected: value ? false : previous.isCollected,
        resetCollectedQuantity: true,
      );
    });

    try {
      final amounts =
      await ApiService.setItemUnavailable(order.id, item.id, value);

      if (!mounted) return;
      setState(() {
        _order = _order?.copyWith(
          totalPrice: amounts.totalPrice,
          originalTotalPrice: amounts.originalTotalPrice,
          removedTotal: amounts.removedTotal,
          refundDue: amounts.refundDue,
          unavailableCount: amounts.unavailableCount,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Нет в наличии: ${item.productName}. Сумма — ${amounts.totalPrice.toStringAsFixed(2)} ₽'
                : 'Возвращено в заказ: ${item.productName}',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _items[index] = previous);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Указать, сколько штук позиции реально нашлось.
  /// Ноль сервер трактует как «товара нет» и исключает позицию из заказа.
  Future<void> _setQuantity(OrderItem item, double quantity) async {
    final order = _order;
    if (order == null) return;
    quantity = OrderItem.roundQuantity(quantity);
    if (quantity < 0 || quantity - item.quantity > 0.0005) return;

    final index = _items.indexWhere((e) => e.id == item.id);
    if (index == -1) return;

    final previous = _items[index];
    final zero = quantity < 0.0005;
    final full = (quantity - item.quantity).abs() < 0.0005;

    setState(() {
      _items[index] = previous.copyWith(
        isUnavailable: zero,
        isCollected: zero ? false : previous.isCollected,
        collectedQuantity: full ? null : quantity,
        resetCollectedQuantity: full || zero,
      );
    });

    try {
      final amounts =
      await ApiService.setItemQuantity(order.id, item.id, quantity);

      if (!mounted) return;
      setState(() {
        _order = _order?.copyWith(
          totalPrice: amounts.totalPrice,
          originalTotalPrice: amounts.originalTotalPrice,
          removedTotal: amounts.removedTotal,
          refundDue: amounts.refundDue,
          unavailableCount: amounts.unavailableCount,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _items[index] = previous);

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

  /// Статусы, при которых сборка ещё не начата
  static const Set<String> _beforePicking = {'new', 'paid', 'receipt_created'};

  /// Статусы, в которых состав заказа ещё можно менять.
  /// Должны совпадать с EDITABLE_STATUSES в orders_api.php — иначе
  /// приложение предлагает действие, на которое сервер отвечает 409.
  static const Set<String> _editable = {
    'new',
    'paid',
    'receipt_created',
    'processing',
  };

  bool get _canEdit => _editable.contains(_order?.status ?? 'new');

  bool get _isPicking => _order?.status == 'processing';

  /// Сборщик берёт заказ в работу. Клиент увидит «Собирается».
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

  /// Ни одной позиции не осталось в наличии — заказ нечего собирать.
  Future<void> _cancelOrder() async {
    final order = _order;
    if (order == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить заказ?'),
        content: Text(
          'В заказе #${order.id} не осталось товаров в наличии.\n\n'
              '${order.isPaidOnline ? 'Заказ оплачен онлайн — возврат ${order.originalTotalPrice.toStringAsFixed(2)} ₽ оформляет магазин.' : 'Клиенту ничего не привозим.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Назад'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отменить заказ'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await ApiService.updateOrderStatus(order.id, 'canceled');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Заказ отменён'),
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
            onPressed: (_order != null && _isPicking) ? _openScanner : null,
            tooltip: 'Сканировать',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrder,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Определяем компактный режим для узких экранов
          final isCompact = constraints.maxWidth < 400;
          return _buildBody(isCompact);
        },
      ),
    );
  }

  Widget _buildBody(bool isCompact) {
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

    final active = _items.where((e) => !e.isUnavailable).toList();
    final collectedCount = active.where((e) => e.isCollected).length;
    final totalCount = active.length;
    final allCollected = totalCount > 0 && collectedCount == totalCount;
    final progressValue = totalCount > 0 ? collectedCount / totalCount : 0.0;
    final nothingLeft = _items.isNotEmpty && active.isEmpty;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildOrderInfoCard(collectedCount, totalCount, progressValue, isCompact),
              _buildItemsListContent(isCompact),
            ],
          ),
        ),
        _buildCompleteButton(allCollected, nothingLeft),
      ],
    );
  }

  Widget _buildPaymentBanner(bool isCompact) {
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
      margin: EdgeInsets.only(bottom: isCompact ? 8 : 12),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 12,
        vertical: isCompact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.shade800, size: isCompact ? 18 : 22),
          SizedBox(width: isCompact ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  order.paymentLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isCompact ? 13 : 15,
                    color: color.shade800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isCompact)
                  Text(
                    order.paymentHint,
                    style: TextStyle(fontSize: 13, color: color.shade800),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Пояснение под суммой: что снято и что с деньгами.
  /// Для оплаченных онлайн возврат пока оформляется вручную —
  /// автоматического частичного возврата ещё нет.
  Widget _buildUnavailableNote(bool isCompact) {
    final order = _order;
    if (order == null) return const SizedBox.shrink();

    final refund = order.refundDue;

    final removedCount = _items.where((e) => e.isUnavailable).length;
    final shortUnits = _items
        .where((e) => e.isPartial && !e.isWeighted)
        .fold<int>(0, (sum, e) => sum + (e.quantity - e.pickedQuantity).round());
    final lighterCount = _items.where((e) => e.isPartial && e.isWeighted).length;

    final parts = <String>[];
    if (removedCount > 0) parts.add('снято позиций: $removedCount');
    if (shortUnits > 0) parts.add('не хватило $shortUnits шт');
    if (lighterCount > 0) parts.add('весовых легче заказа: $lighterCount');

    final headline = parts.isEmpty
        ? 'Сумма уменьшена на ${order.removedTotal.toStringAsFixed(2)} ₽'
        : '${parts.join(', ')} — на ${order.removedTotal.toStringAsFixed(2)} ₽';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 10,
        vertical: isCompact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline[0].toUpperCase() + headline.substring(1),
            style: TextStyle(
              fontSize: isCompact ? 12 : 13,
              fontWeight: FontWeight.w600,
              color: Colors.red[800],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (!isCompact)
            const SizedBox(height: 2),
          Text(
            refund > 0
                ? 'Оплачено онлайн — возврат ${refund.toStringAsFixed(2)} ₽ оформляет магазин'
                : 'Взять с клиента: ${order.totalPrice.toStringAsFixed(2)} ₽',
            style: TextStyle(fontSize: isCompact ? 11 : 12, color: Colors.red[800]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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

  Widget _buildScheduleBanner() {
    final order = _order!;
    final waiting = order.isWaitingRelease;
    final color = waiting ? Colors.teal : Colors.indigo;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Доставка ко времени: ${order.scheduleLabel}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color.shade800,
                  ),
                ),
                if (waiting && order.releaseLabel.isNotEmpty)
                  Text(
                    'Сборка откроется в ${order.releaseLabel}',
                    style: TextStyle(fontSize: 13, color: color.shade800),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderInfoCard(
      int collectedCount,
      int totalCount,
      double progressValue,
      bool isCompact,
      ) {
    if (_order == null) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.all(isCompact ? 8 : 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(isCompact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPaymentBanner(isCompact),
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
                        style: TextStyle(
                          fontSize: isCompact ? 14 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: isCompact ? 2 : 4),
                      Row(
                        children: [
                          Icon(Icons.phone, size: isCompact ? 12 : 14, color: Colors.grey),
                          SizedBox(width: isCompact ? 2 : 4),
                          Expanded(
                            child: Text(
                              _order!.customerPhone.isNotEmpty
                                  ? _order!.customerPhone
                                  : 'Нет номера',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: isCompact ? 12 : 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: isCompact ? 8 : 16),
                // Цена
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_order!.hasUnavailable)
                      Text(
                        '${_order!.originalTotalPrice.toStringAsFixed(2)} ₽',
                        style: TextStyle(
                          fontSize: isCompact ? 11 : 13,
                          color: Colors.grey,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    Text(
                      '${_order!.totalPrice.toStringAsFixed(2)} ₽',
                      style: TextStyle(
                        fontSize: isCompact ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_order!.hasUnavailable) ...[
              SizedBox(height: isCompact ? 6 : 8),
              _buildUnavailableNote(isCompact),
            ],
            if (_order!.address.isNotEmpty) ...[
              SizedBox(height: isCompact ? 6 : 8),
              Row(
                children: [
                  Icon(Icons.location_on, size: isCompact ? 12 : 14, color: Colors.grey),
                  SizedBox(width: isCompact ? 2 : 4),
                  Expanded(
                    child: Text(
                      _order!.address,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: isCompact ? 12 : 13,
                      ),
                      maxLines: isCompact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            if (_order!.comment.trim().isNotEmpty) ...[
              SizedBox(height: isCompact ? 6 : 8),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 8 : 10,
                  vertical: isCompact ? 6 : 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.deepOrange.withOpacity(0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.comment_outlined,
                        size: isCompact ? 14 : 16,
                        color: Colors.deepOrange[700],
                      ),
                    ),
                    SizedBox(width: isCompact ? 6 : 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Комментарий к заказу',
                            style: TextStyle(
                              fontSize: isCompact ? 11 : 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.deepOrange[800],
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            _order!.comment.trim(),
                            style: TextStyle(
                              fontSize: isCompact ? 12 : 13,
                              color: Colors.deepOrange[900],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(height: isCompact ? 8 : 12),
            // Прогресс сборки


            SizedBox(height: isCompact ? 8 : 12),
            // Прогресс сборки
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Собрано: $collectedCount из $totalCount',
                  style: TextStyle(fontSize: isCompact ? 12 : 13),
                ),
                Text(
                  '${(progressValue * 100).round()}%',
                  style: TextStyle(
                    fontSize: isCompact ? 12 : 13,
                    fontWeight: FontWeight.bold,
                    color: progressValue == 1.0 ? Colors.green : Colors.blue,
                  ),
                ),
              ],
            ),
            SizedBox(height: isCompact ? 4 : 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progressValue,
                minHeight: isCompact ? 6 : 8,
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

    return Column(
      children: [
        if (!_canEdit)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Заказ уже отправлен — состав и сумму изменить нельзя',
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => _buildItemTile(_items[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildItemsListContent(bool isCompact) {
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_rounded, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('В заказе нет товаров'),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (!_canEdit)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Заказ уже отправлен — состав и сумму изменить нельзя',
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                  ),
                ),
              ],
            ),
          ),
        ...List.generate(
          _items.length,
              (index) => Column(
            children: [
              _buildItemTile(_items[index]),
              if (index < _items.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(height: 1),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItemTile(OrderItem item) {
    final missing = item.isUnavailable;
    final dimmed = missing || item.isCollected;
    // После отправки заказа сервер откажет в любой правке состава,
    // поэтому не показываем действия, которые заведомо не пройдут.
    final locked = !_isPicking;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      // У отсутствующего товара галочку сборки ставить не из чего.
      leading: Checkbox(
        value: item.isCollected,
        onChanged: (missing || locked)
            ? null
            : (value) => _updateItemStatus(item, value ?? false),
        activeColor: Colors.green,
      ),
      title: Text(
        item.productName,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          decoration:
          dimmed ? TextDecoration.lineThrough : TextDecoration.none,
          color: missing ? Colors.red[400] : (dimmed ? Colors.grey : null),
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.isWeighted
                ? '${item.quantityText(item.pickedQuantity)}  •  ${item.price.toStringAsFixed(2)} ₽/кг'
                    '  =  ${item.subtotal.toStringAsFixed(2)} ₽'
                : '× ${item.pickedQuantity.round()}  •  ${item.price.toStringAsFixed(2)} ₽'
                    '  =  ${item.subtotal.toStringAsFixed(2)} ₽',
            style: const TextStyle(fontSize: 12),
          ),
          if (item.isPartial)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Заказано ${item.quantityText(item.quantity)} — оплатит '
                    '${item.subtotal.toStringAsFixed(2)} ₽ вместо '
                    '${item.orderedSubtotal.toStringAsFixed(2)} ₽',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange[800],
                ),
              ),
            ),
          if (missing)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Нет в наличии — вычтено из суммы',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.red[700],
                ),
              ),
            ),
          if (!locked && !missing && item.isWeighted)
            _buildWeightRow(item),
          if (!locked && !missing && !item.isWeighted && item.quantity > 1)
            _buildQuantityStepper(item),
        ],
      ),
      trailing: locked
          ? null
          : IconButton(
        icon: Icon(
          missing ? Icons.undo : Icons.remove_shopping_cart_outlined,
          color: missing ? Colors.blue : Colors.red[400],
        ),
        tooltip: missing ? 'Вернуть в заказ' : 'Нет в наличии',
        onPressed: () => _setUnavailable(item, !missing),
      ),
    );
  }

  /// Сколько штук нашлось. Минус доводит до нуля — это то же самое,
  /// что «нет в наличии», поэтому отдельного подтверждения там не нужно.
  Widget _buildQuantityStepper(OrderItem item) {
    final picked = item.pickedQuantity;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Text('Нашли:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          _stepperButton(
            icon: Icons.remove,
            onTap: picked > 0 ? () => _setQuantity(item, picked - 1) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '${picked.round()} из ${item.quantity.round()}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          _stepperButton(
            icon: Icons.add,
            onTap: picked < item.quantity
                ? () => _setQuantity(item, picked + 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildWeightRow(OrderItem item) {
    final weighed = item.quantityText(item.pickedQuantity).replaceAll(' кг', '');

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Взвесили:', style: TextStyle(fontSize: 12)),
          Text(
            '$weighed из ${item.quantityText(item.quantity)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          OutlinedButton.icon(
            onPressed: () => _askWeight(item),
            icon: const Icon(Icons.scale_outlined, size: 18),
            label: const Text('Указать вес'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _askWeight(OrderItem item) async {
    final controller = TextEditingController(
      text: item.quantityText(item.pickedQuantity).replaceAll(' кг', ''),
    );
    String? error;

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void submit() {
            final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
            if (value == null || value <= 0) {
              setLocal(() => error = 'Введите вес, например 0,46');
              return;
            }
            if (value - item.quantity > 0.0005) {
              setLocal(() => error = 'Не больше заказанного: ${item.quantityText(item.quantity)}');
              return;
            }
            Navigator.pop(ctx, value);
          }

          return AlertDialog(
            title: Text(item.productName),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Заказано ${item.quantityText(item.quantity)}. '
                    'Если на весах больше — оставьте заказанный вес.'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Фактический вес',
                    suffixText: 'кг',
                    errorText: error,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: submit,
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );

    controller.dispose();
    if (result != null) {
      await _setQuantity(item, result);
    }
  }

  Widget _stepperButton({required IconData icon, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: onTap == null ? Colors.grey[300]! : Colors.grey[500]!,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? Colors.grey[400] : Colors.black87,
        ),
      ),
    );
  }

  /// Кнопка внизу зависит от того, на каком шаге заказ:
  ///   принят      → «Начать сборку»
  ///   собирается  → «Готов к доставке» (когда всё собрано)
  ///   отправлен   → ничего не делаем
  Widget _buildCompleteButton(bool allCollected, bool nothingLeft) {
    final status = _order?.status ?? 'new';

    final String label;
    final IconData icon;
    final VoidCallback? action;
    final Color? color;

    if (status == 'scheduled') {
      final opensAt = _order?.releaseLabel ?? '';
      label = opensAt.isNotEmpty ? 'Сборка откроется в $opensAt' : 'Заказ ко времени';
      icon = Icons.schedule;
      action = null;
      color = null;
    } else if (nothingLeft && !_beforePicking.contains(status)) {
      // Собирать нечего — все позиции отмечены отсутствующими.
      // Отправлять пустой заказ курьеру бессмысленно, остаётся отменить.
      label = 'Отменить заказ';
      icon = Icons.cancel_outlined;
      action = _isLoading ? null : _cancelOrder;
      color = Colors.red;
    } else if (_beforePicking.contains(status)) {
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
          foregroundColor: color != null ? Colors.white : null,
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