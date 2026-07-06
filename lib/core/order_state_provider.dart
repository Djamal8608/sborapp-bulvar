import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CollectedState {
  final int orderId;
  final int itemId;
  final bool isCollected;

  const CollectedState({
    required this.orderId,
    required this.itemId,
    this.isCollected = false,
  });
}

class OrderStateRepository {
  static const String _storageKey = 'order_collected_states';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> initStorage() async {}

  Future<bool> saveState(CollectedState state) async {
    final storedData = await _storage.read(key: _storageKey);

    Map<String, dynamic> rawStates = {};
    if (storedData != null && storedData.isNotEmpty) {
      try {
        rawStates = jsonDecode(storedData) as Map<String, dynamic>;
      } catch (_) {
        rawStates = {};
      }
    }

    final orderKey = state.orderId.toString();
    final List<int> items =
        (rawStates[orderKey] as List?)?.map((e) => e as int).toList() ?? [];

    if (state.isCollected) {
      if (!items.contains(state.itemId)) {
        items.add(state.itemId);
      }
    } else {
      items.remove(state.itemId);
    }

    rawStates[orderKey] = items;
    await _storage.write(
      key: _storageKey,
      value: jsonEncode(rawStates),
    );

    return true;
  }

  Future<Map<int, bool>> loadStatesForOrder(int orderId) async {
    final storedData = await _storage.read(key: _storageKey);

    Map<String, dynamic> rawStates = {};
    if (storedData != null && storedData.isNotEmpty) {
      try {
        rawStates = jsonDecode(storedData) as Map<String, dynamic>;
      } catch (_) {
        rawStates = {};
      }
    }

    final orderKey = orderId.toString();
    final List<int> items =
        (rawStates[orderKey] as List?)?.map((e) => e as int).toList() ?? [];

    return Map<int, bool>.fromEntries(
      items.map((itemId) => MapEntry(itemId, true)),
    );
  }

  Future<void> clearStateForOrder(int orderId) async {
    final storedData = await _storage.read(key: _storageKey);

    Map<String, dynamic> rawStates = {};
    if (storedData != null && storedData.isNotEmpty) {
      try {
        rawStates = jsonDecode(storedData) as Map<String, dynamic>;
      } catch (_) {
        rawStates = {};
      }
    }

    rawStates.remove(orderId.toString());

    await _storage.write(
      key: _storageKey,
      value: jsonEncode(rawStates),
    );
  }
}

final OrderStateRepository instance = OrderStateRepository();