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

    final order = _order!;
    final isCash = !order.isPaidOnline && order.paymentMethod == 'cash';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isCash ? 'Пробить чек и отправить на доставку?' : 'Отправить на доставку?'),
        content: Text(
          isCash
              ? 'Заказ будет отмечен как готов к доставке.\n\n'
              '✓ Сразу будет пробит чек на кассе '
              'на сумму ${order.totalPrice.toStringAsFixed(2)} ₽.\n'
              'Доставщик сможет забрать посылку.'
              : 'Заказ будет отмечен как готов к доставке.\n'
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
      // 1. Сначала пробиваем чек (только для наличных)
      if (isCash) {
        try {
          await ApiService.checkoutOrder(
            orderId: order.id,
            items: order.items.where((e) => !e.isUnavailable).toList(),
            totalAmount: order.totalPrice,
            paymentType: 'cash',
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✓ Чек отправлен на кассу'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          // Чек не пробился — спрашиваем, что делать
          if (!mounted) return;

          final proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Чек не пробился'),
              content: Text(
                'Ошибка: $e\n\n'
                    'Заказ всё равно отправить на доставку?\n\n'
                    '⚠ Чек придётся пробить вручную на кассе.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Отправить без чека'),
                ),
              ],
            ),
          );

          if (proceed != true) {
            setState(() => _isLoading = false);
            return;
          }
        }
      }

      // 2. Переводим заказ в статус 'packed'
      await ApiService.updateOrderStatus(order.id, 'packed');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCash
                ? '✓ Чек пробит и заказ готов к доставке!'
                : '✓ Заказ готов к доставке!',
          ),
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
            // Сканирование тоже меняет состав — после отправки сервер откажет.
            onPressed: (_order != null && _canEdit) ? _openScanner : null,
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

    // Отсутствующие позиции не участвуют в прогрессе: собрать их нельзя,
    // и если оставить их в знаменателе, заказ никогда не дойдёт до 100%.
    final active = _items.where((e) => !e.isUnavailable).toList();
    final collectedCount = active.where((e) => e.isCollected).length;
    final totalCount = active.length;
    final allCollected = totalCount > 0 && collectedCount == totalCount;
    final progressValue = totalCount > 0 ? collectedCount / totalCount : 0.0;
    final nothingLeft = _items.isNotEmpty && active.isEmpty;

    return Column(
      children: [
        _buildOrderInfoCard(collectedCount, totalCount, progressValue),
        Expanded(child: _buildItemsList()),
        _buildCompleteButton(allCollected, nothingLeft),
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

  /// Пояснение под суммой: что снято и что с деньгами.
  /// Для оплаченных онлайн возврат пока оформляется вручную —
  /// автоматического частичного возврата ещё нет.
  Widget _buildUnavailableNote() {
    final order = _order;
    if (order == null) return const SizedBox.shrink();

    final refund = order.refundDue;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Снято позиций: ${order.unavailableCount} '
                'на ${order.removedTotal.toStringAsFixed(2)} ₽',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.red[800],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            refund > 0
                ? 'Оплачено онлайн — возврат ${refund.toStringAsFixed(2)} ₽ оформляет магазин'
                : 'Взять с клиента: ${order.totalPrice.toStringAsFixed(2)} ₽',
            style: TextStyle(fontSize: 12, color: Colors.red[800]),
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
                // Цена: если что-то сняли, показываем и старую сумму —
                // сборщик должен взять с клиента именно новую.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_order!.hasUnavailable)
                      Text(
                        '${_order!.originalTotalPrice.toStringAsFixed(2)} ₽',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
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
              ],
            ),
            if (_order!.hasUnavailable) ...[
              const SizedBox(height: 8),
              _buildUnavailableNote(),
            ],
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

  Widget _buildItemTile(OrderItem item) {
    final missing = item.isUnavailable;
    final dimmed = missing || item.isCollected;
    // После отправки заказа сервер откажет в любой правке состава,
    // поэтому не показываем действия, которые заведомо не пройдут.
    final locked = !_canEdit;

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
            '× ${item.quantity}  •  ${item.price.toStringAsFixed(2)} ₽'
                '  =  ${item.subtotal.toStringAsFixed(2)} ₽',
            style: const TextStyle(fontSize: 12),
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

    if (nothingLeft && !_beforePicking.contains(status)) {
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