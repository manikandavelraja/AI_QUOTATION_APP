import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/database_service.dart';
import '../../domain/entities/supplier_order.dart';

class SupplierOrderState {
  final List<SupplierOrder> orders;
  final bool isLoading;
  final String? error;

  SupplierOrderState({
    this.orders = const [],
    this.isLoading = false,
    this.error,
  });

  SupplierOrderState copyWith({
    List<SupplierOrder>? orders,
    bool? isLoading,
    String? error,
  }) {
    return SupplierOrderState(
      orders: orders ?? this.orders,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class SupplierOrderNotifier extends StateNotifier<SupplierOrderState> {
  final DatabaseService _databaseService;

  SupplierOrderNotifier(this._databaseService) : super(SupplierOrderState()) {
    loadSupplierOrders();
  }

  Future<void> loadSupplierOrders() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final orders = await _databaseService.getAllSupplierOrders();
      state = state.copyWith(
        orders: orders,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  Future<SupplierOrder?> addSupplierOrder(SupplierOrder order) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final id = await _databaseService.insertSupplierOrder(order);
      await loadSupplierOrders();
      return order.copyWith(id: id);
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
      rethrow;
    }
  }

  Future<void> updateSupplierOrder(SupplierOrder order) async {
    try {
      await _databaseService.updateSupplierOrder(order);
      await loadSupplierOrders();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteSupplierOrder(String id) async {
    try {
      await _databaseService.deleteSupplierOrder(id);
      await loadSupplierOrders();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<SupplierOrder?> getSupplierOrderById(String id) async {
    return await _databaseService.getSupplierOrderById(id);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final supplierOrderProvider = StateNotifierProvider<SupplierOrderNotifier, SupplierOrderState>((ref) {
  return SupplierOrderNotifier(DatabaseService.instance);
});

