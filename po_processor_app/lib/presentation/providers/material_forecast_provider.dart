import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/material_forecast.dart';
import '../../data/services/material_forecast_service.dart';

class MaterialForecastState {
  final MaterialForecast? forecast;
  final bool isLoading;
  final String? error;
  final List<String> availableMaterialCodes;

  const MaterialForecastState({
    this.forecast,
    this.isLoading = false,
    this.error,
    this.availableMaterialCodes = const [],
  });

  MaterialForecastState copyWith({
    MaterialForecast? forecast,
    bool? isLoading,
    String? error,
    List<String>? availableMaterialCodes,
  }) {
    return MaterialForecastState(
      forecast: forecast ?? this.forecast,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      availableMaterialCodes: availableMaterialCodes ?? this.availableMaterialCodes,
    );
  }
}

class MaterialForecastNotifier extends StateNotifier<MaterialForecastState> {
  final MaterialForecastService _service = MaterialForecastService();

  MaterialForecastNotifier() : super(const MaterialForecastState()) {
    _loadAvailableMaterialCodes();
  }

  Future<void> _loadAvailableMaterialCodes() async {
    try {
      final codes = await _service.getAllMaterialCodes();
      state = state.copyWith(availableMaterialCodes: codes);
    } catch (e) {
      // Silently fail - codes are optional
    }
  }

  /// Public method to reload available material codes
  Future<void> reloadMaterialCodes() async {
    await _loadAvailableMaterialCodes();
  }

  Future<void> analyzeMaterial(String materialCode) async {
    debugPrint('📊 [Material Forecast Provider] analyzeMaterial called with: "$materialCode"');
    
    if (materialCode.trim().isEmpty) {
      debugPrint('⚠️ [Material Forecast Provider] Material code is empty');
      state = state.copyWith(
        error: 'Please enter a material code',
        forecast: null,
        isLoading: false,
      );
      return;
    }

    debugPrint('📊 [Material Forecast Provider] Setting loading state to true');
    state = state.copyWith(isLoading: true, error: null);

    try {
      debugPrint('📊 [Material Forecast Provider] Calling service.analyzeMaterial...');
      final forecast = await _service.analyzeMaterial(materialCode.trim());
      
      if (forecast == null) {
        debugPrint('❌ [Material Forecast Provider] No forecast returned (null)');
        state = state.copyWith(
          error: 'No procurement data found for material code: $materialCode',
          forecast: null,
          isLoading: false,
        );
      } else {
        debugPrint('✅ [Material Forecast Provider] Forecast received successfully');
        debugPrint('✅ [Material Forecast Provider] Purchase count: ${forecast.purchaseCountLast12Months}');
        debugPrint('✅ [Material Forecast Provider] Total quantity: ${forecast.totalQuantityLast12Months}');
        state = state.copyWith(
          forecast: forecast,
          isLoading: false,
          error: null,
        );
      }
    } catch (e) {
      debugPrint('❌ [Material Forecast Provider] Error: ${e.toString()}');
      debugPrint('❌ [Material Forecast Provider] Stack trace: ${StackTrace.current}');
      state = state.copyWith(
        error: 'Error analyzing material: ${e.toString()}',
        forecast: null,
        isLoading: false,
      );
    }
  }

  void clearForecast() {
    state = state.copyWith(
      forecast: null,
      error: null,
    );
  }
}

final materialForecastProvider =
    StateNotifierProvider<MaterialForecastNotifier, MaterialForecastState>(
  (ref) => MaterialForecastNotifier(),
);

