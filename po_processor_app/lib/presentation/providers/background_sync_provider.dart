import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Progress for one type of sync (inquiry or PO). Both can run in parallel.
class SyncProgress {
  final int current;
  final int total;
  final int successCount;
  final int failCount;
  final bool isActive;

  const SyncProgress({
    this.current = 0,
    this.total = 0,
    this.successCount = 0,
    this.failCount = 0,
    this.isActive = false,
  });

  String get progressLabel =>
      total > 0 ? 'Processing $current of $total items' : 'Processing...';
}

/// Combined state: inquiry and PO sync run independently in parallel.
class BackgroundSyncState {
  final SyncProgress? inquiryProgress;
  final SyncProgress? poProgress;

  const BackgroundSyncState({
    this.inquiryProgress,
    this.poProgress,
  });

  bool get isActive =>
      (inquiryProgress?.isActive ?? false) || (poProgress?.isActive ?? false);
}

class BackgroundSyncNotifier extends ChangeNotifier {
  SyncProgress? _inquiryProgress;
  SyncProgress? _poProgress;

  BackgroundSyncState get state => BackgroundSyncState(
        inquiryProgress: _inquiryProgress,
        poProgress: _poProgress,
      );

  void startInquirySync({int total = 0}) {
    _inquiryProgress = SyncProgress(
      current: 0,
      total: total,
      successCount: 0,
      failCount: 0,
      isActive: true,
    );
    notifyListeners();
  }

  void setInquiryProgress({
    required int current,
    required int total,
    required int successCount,
    required int failCount,
  }) {
    if (_inquiryProgress == null) return;
    _inquiryProgress = SyncProgress(
      current: current,
      total: total,
      successCount: successCount,
      failCount: failCount,
      isActive: true,
    );
    notifyListeners();
  }

  void setInquiryComplete({
    required int total,
    required int successCount,
    required int failCount,
  }) {
    _inquiryProgress = SyncProgress(
      current: total,
      total: total,
      successCount: successCount,
      failCount: failCount,
      isActive: false,
    );
    notifyListeners();
  }

  void setInquiryError() {
    _inquiryProgress = null;
    notifyListeners();
  }

  void startPOSync({int total = 0}) {
    _poProgress = SyncProgress(
      current: 0,
      total: total,
      successCount: 0,
      failCount: 0,
      isActive: true,
    );
    notifyListeners();
  }

  void setPOProgress({
    required int current,
    required int total,
    required int successCount,
    required int failCount,
  }) {
    if (_poProgress == null) return;
    _poProgress = SyncProgress(
      current: current,
      total: total,
      successCount: successCount,
      failCount: failCount,
      isActive: true,
    );
    notifyListeners();
  }

  void setPOComplete({
    required int total,
    required int successCount,
    required int failCount,
  }) {
    _poProgress = SyncProgress(
      current: total,
      total: total,
      successCount: successCount,
      failCount: failCount,
      isActive: false,
    );
    notifyListeners();
  }

  void setPOError() {
    _poProgress = null;
    notifyListeners();
  }
}

final backgroundSyncProvider =
    ChangeNotifierProvider<BackgroundSyncNotifier>((ref) {
  return BackgroundSyncNotifier();
});
