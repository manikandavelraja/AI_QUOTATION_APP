import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/database_service.dart';
import '../../domain/entities/customer_inquiry.dart';

class InquiryState {
  final List<CustomerInquiry> inquiries;
  final bool isLoading;
  final String? error;

  InquiryState({
    this.inquiries = const [],
    this.isLoading = false,
    this.error,
  });

  InquiryState copyWith({
    List<CustomerInquiry>? inquiries,
    bool? isLoading,
    String? error,
  }) {
    return InquiryState(
      inquiries: inquiries ?? this.inquiries,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class InquiryNotifier extends StateNotifier<InquiryState> {
  final DatabaseService _databaseService;

  InquiryNotifier(this._databaseService) : super(InquiryState()) {
    loadInquiries();
  }

  Future<void> loadInquiries() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final inquiries = await _databaseService.getAllCustomerInquiries();
      state = state.copyWith(
        inquiries: inquiries,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  Future<CustomerInquiry?> addInquiry(CustomerInquiry inquiry) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final id = await _databaseService.insertCustomerInquiry(inquiry);
      await loadInquiries();
      return inquiry.copyWith(id: id);
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
      rethrow;
    }
  }

  Future<void> updateInquiry(CustomerInquiry inquiry) async {
    try {
      await _databaseService.updateCustomerInquiry(inquiry);
      await loadInquiries();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteInquiry(String id) async {
    try {
      await _databaseService.deleteCustomerInquiry(id);
      await loadInquiries();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<CustomerInquiry?> getInquiryById(String id) async {
    return await _databaseService.getCustomerInquiryById(id);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final inquiryProvider = StateNotifierProvider<InquiryNotifier, InquiryState>((ref) {
  return InquiryNotifier(DatabaseService.instance);
});

