import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/database_service.dart';
import '../../domain/entities/delivery_document.dart';

class DeliveryState {
  final List<DeliveryDocument> documents;
  final bool isLoading;
  final String? error;

  DeliveryState({
    this.documents = const [],
    this.isLoading = false,
    this.error,
  });

  DeliveryState copyWith({
    List<DeliveryDocument>? documents,
    bool? isLoading,
    String? error,
  }) {
    return DeliveryState(
      documents: documents ?? this.documents,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class DeliveryNotifier extends StateNotifier<DeliveryState> {
  final DatabaseService _databaseService;

  DeliveryNotifier(this._databaseService) : super(DeliveryState()) {
    loadDeliveryDocuments();
  }

  Future<void> loadDeliveryDocuments() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final documents = await _databaseService.getAllDeliveryDocuments();
      state = state.copyWith(
        documents: documents,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  Future<DeliveryDocument?> addDeliveryDocument(DeliveryDocument document) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final id = await _databaseService.insertDeliveryDocument(document);
      await loadDeliveryDocuments();
      return document.copyWith(id: id);
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
      rethrow;
    }
  }

  Future<void> updateDeliveryDocument(DeliveryDocument document) async {
    try {
      await _databaseService.updateDeliveryDocument(document);
      await loadDeliveryDocuments();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteDeliveryDocument(String id) async {
    try {
      await _databaseService.deleteDeliveryDocument(id);
      await loadDeliveryDocuments();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<DeliveryDocument?> getDeliveryDocumentById(String id) async {
    return await _databaseService.getDeliveryDocumentById(id);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final deliveryProvider = StateNotifierProvider<DeliveryNotifier, DeliveryState>((ref) {
  return DeliveryNotifier(DatabaseService.instance);
});

