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

  /// Update existing quotation by adding prices to pending items
  /// Returns the updated quotation with all items marked as ready
  Future<Quotation?> updateExistingQuote({
    required String quotationId,
    required Map<String, double> itemPrices, // Map of item ID or item name to price
  }) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      
      // Get the existing quotation
      final quotation = await _databaseService.getQuotationById(quotationId);
      if (quotation == null) {
        throw Exception('Quotation not found');
      }
      
      // Update pending items with prices
      final updatedItems = quotation.items.map((item) {
        // Check if this item needs to be updated
        if (item.status == 'pending') {
          // Try to find price by item ID, then by item name
          double? newPrice = itemPrices[item.id] ?? itemPrices[item.itemName];
          
          if (newPrice != null && newPrice > 0) {
            // Update the item with the new price
            final newTotal = newPrice * item.quantity;
            return item.copyWith(
              unitPrice: newPrice,
              total: newTotal,
              isPriced: true,
              status: 'ready',
            );
          }
        }
        // Return item as-is if not pending or no price provided
        return item;
      }).toList();
      
      // Recalculate total amount
      final subtotal = updatedItems.fold<double>(
        0.0,
        (sum, item) => sum + item.total,
      );
      final vat = subtotal * 0.05;
      final grandTotal = subtotal + vat;
      
      // Create updated quotation
      final updatedQuotation = quotation.copyWith(
        items: updatedItems,
        totalAmount: grandTotal,
        updatedAt: DateTime.now(),
      );
      
      // Update in database
      await _databaseService.updateQuotation(updatedQuotation);
      await loadQuotations();
      
      return updatedQuotation;
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
      rethrow;
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final quotationProvider = StateNotifierProvider<QuotationNotifier, QuotationState>((ref) {
  return QuotationNotifier(DatabaseService.instance);
});

