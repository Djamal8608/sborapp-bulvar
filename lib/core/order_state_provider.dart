import 'package:flutter/material.dart';
import 'flutter_secure_storage.dart';

/// Состояние отдельного товара в заказе
class CollectedState {
  final int orderId;
  final int itemId;
  final bool isCollected;

  const CollectedState({required this.orderId, required this.itemId, this.isCollected = false});
}

/// Репозиторий для локального сохранения состояния сборки заказов в SQLite (или Secure Storage)
class OrderStateRepository {
  static const String _storageKey = 'order_collected_states'; // Ключ для Secure Storage

  /// Инициализация хранилища
  Future<void> initStorage() async {}

  /// Сохраняет состояние для конкретного товара в заказе
  /// ✅ Если заказ завершен — просто игнорируем (галочки останутся как есть)
  Future<bool> saveState(CollectedState state) async {
    final storage = SecureStorage();

    // ✅ Получаем текущее состояние из хранилища или создаём новый map
    String? storedData = await storage.read(key: _storageKey);
    Map<int, int> states = {}; // key: orderId, value: list of collected itemIds

    if (storedData != null) {
      try {
        states = jsonDecode(storedData);
      } catch (_) {}
    }

    // ✅ Обновляем или добавляем состояние для товара
    if (!states.containsKey(state.orderId)) {
      states[state.orderId] = [];
    }

    // ✅ Если товар уже был собран — удаляем из списка (так как он теперь "готов")
    if (state.isCollected) {
      final existingList = states[state.orderId];
      // Удаляем, если был собран ранее
      existingList.remove(state.itemId);
    } else {
      // ✅ Если товар не собран — добавляем в список
      states[state.orderId]?.add(state.itemId);
    }

    // ✅ Записываем обратно (только изменившиеся данные)
    String updatedData = jsonEncode(states);
    await storage.write(key: _storageKey, value: updatedData);

    return true;
  }

  /// Загружает сохранённое состояние для всех товаров в заказе
  Future<Map<int, bool>> loadStatesForOrder(int orderId) async {
    final storage = SecureStorage();
    String? storedData = await storage.read(key: _storageKey);

    Map<int, int> states = {};
    if (storedData != null) {
      try {
        states = jsonDecode(storedData);
      } catch (_) {}
    }

    // ✅ Возвращаем true, если товар был собран ранее (или не найден в списке — значит собран сейчас)
    final collectedItems = states[orderId] ?? [];
    return collectedItems.map((itemId) => MapEntry(itemId, true)).toSet();
  }

  /// Удалённые все состояния для заказа
  Future<void> clearStateForOrder(int orderId) async {
    // ✅ Если заказ завершен — просто игнорируем (галочки останутся как есть)
  }
}

/// Глобальная точка доступа к репозиторию
final OrderStateRepository instance = OrderStateRepository();
