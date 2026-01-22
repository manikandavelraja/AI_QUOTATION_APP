import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/database_service.dart';
import '../../domain/entities/purchase_order.dart';

class POState {
  final List<PurchaseOrder> purchaseOrders;
  final bool isLoading;
  final String? error;
  final Map<String, dynamic>? dashboardStats;

  POState({
    this.purchaseOrders = const [],
    this.isLoading = false,
    this.error,
    this.dashboardStats,
  });

  POState copyWith({
    List<PurchaseOrder>? purchaseOrders,
    bool? isLoading,
    String? error,
    Map<String, dynamic>? dashboardStats,
  }) {
    return POState(
      purchaseOrders: purchaseOrders ?? this.purchaseOrders,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      dashboardStats: dashboardStats ?? this.dashboardStats,
    );
  }
}

class PONotifier extends StateNotifier<POState> {
  final DatabaseService _databaseService;

  PONotifier(this._databaseService) : super(POState()) {
    loadPurchaseOrders();
  }

  Future<void> loadPurchaseOrders() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final pos = await _databaseService.getAllPurchaseOrders();
      final stats = await _databaseService.getDashboardStats();
      state = state.copyWith(
        purchaseOrders: pos,
        dashboardStats: stats,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  Future<PurchaseOrder?> addPurchaseOrder(PurchaseOrder po) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final id = await _databaseService.insertPurchaseOrder(po);
      await loadPurchaseOrders();
      // Return the saved PO with the ID
      final savedPO = po.copyWith(id: id);
      return savedPO;
    } catch (e) {
      // Clear stale data and show error
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
        // Don't clear purchaseOrders - keep existing data, just show error
      );
      rethrow; // Re-throw so upload screen can handle it
    }
  }
  
  /// Clear error state - useful when retrying after an error
  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<void> updatePurchaseOrder(PurchaseOrder po) async {
    try {
      await _databaseService.updatePurchaseOrder(po);
      await loadPurchaseOrders();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deletePurchaseOrder(String id) async {
    try {
      await _databaseService.deletePurchaseOrder(id);
      await loadPurchaseOrders();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<PurchaseOrder?> getPurchaseOrderById(String id) async {
    return await _databaseService.getPurchaseOrderById(id);
  }
}

extension POStateExtension on POState {
  List<PurchaseOrder> get expiringPOs {
    return purchaseOrders.where((po) => po.isExpiringSoon).toList();
  }

  List<PurchaseOrder> get expiredPOs {
    return purchaseOrders.where((po) => po.isExpired).toList();
  }
}

final poProvider = StateNotifierProvider<PONotifier, POState>((ref) {
  return PONotifier(DatabaseService.instance);
});

