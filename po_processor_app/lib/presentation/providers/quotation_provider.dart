import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/database_service.dart';
import '../../domain/entities/quotation.dart';

class QuotationState {
  final List<Quotation> quotations;
  final bool isLoading;
  final String? error;

  QuotationState({
    this.quotations = const [],
    this.isLoading = false,
    this.error,
  });

  QuotationState copyWith({
    List<Quotation>? quotations,
    bool? isLoading,
    String? error,
  }) {
    return QuotationState(
      quotations: quotations ?? this.quotations,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class QuotationNotifier extends StateNotifier<QuotationState> {
  final DatabaseService _databaseService;

  QuotationNotifier(this._databaseService) : super(QuotationState()) {
    loadQuotations();
  }

  Future<void> loadQuotations() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final quotations = await _databaseService.getAllQuotations();
      state = state.copyWith(
        quotations: quotations,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  Future<Quotation?> addQuotation(Quotation quotation) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final id = await _databaseService.insertQuotation(quotation);
      await loadQuotations();
      return quotation.copyWith(id: id);
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
      rethrow;
    }
  }

  Future<void> updateQuotation(Quotation quotation) async {
    try {
      await _databaseService.updateQuotation(quotation);
      await loadQuotations();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteQuotation(String id) async {
    try {
      await _databaseService.deleteQuotation(id);
      await loadQuotations();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<Quotation?> getQuotationById(String id) async {
    return await _databaseService.getQuotationById(id);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final quotationProvider = StateNotifierProvider<QuotationNotifier, QuotationState>((ref) {
  return QuotationNotifier(DatabaseService.instance);
});

