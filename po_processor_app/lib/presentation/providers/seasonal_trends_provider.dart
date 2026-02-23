import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/vbelt_prediction_service.dart';

class SeasonalTrendsState {
  final PredictionResult? prediction;
  final bool isLoading;
  final String? error;

  SeasonalTrendsState({
    this.prediction,
    this.isLoading = false,
    this.error,
  });

  SeasonalTrendsState copyWith({
    PredictionResult? prediction,
    bool? isLoading,
    String? error,
  }) {
    return SeasonalTrendsState(
      prediction: prediction ?? this.prediction,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class SeasonalTrendsNotifier extends StateNotifier<SeasonalTrendsState> {
  SeasonalTrendsNotifier() : super(SeasonalTrendsState());

  Future<void> loadPredictions({
    required String region,
    required String season,
    required int month,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final prediction = await VBeltPredictionService.predictDemand(
        region: region,
        season: season,
        month: month,
      );

      state = state.copyWith(
        prediction: prediction,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }
}

final seasonalTrendsProvider =
    StateNotifierProvider<SeasonalTrendsNotifier, SeasonalTrendsState>(
  (ref) => SeasonalTrendsNotifier(),
);

