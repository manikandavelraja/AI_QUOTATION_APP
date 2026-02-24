import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive_helper.dart';
import '../../domain/entities/material_forecast.dart';
import '../providers/seasonal_trends_provider.dart';
import '../providers/material_forecast_provider.dart';
import '../utils/planning_recommendations_helper.dart';

/// Overall Recommendation aggregates recommendations from Seasonal Trends,
/// Material Forecasting, and Inventory Management into a single paragraph.
class OverallRecommendationScreen extends ConsumerStatefulWidget {
  final bool embedInDashboard;

  const OverallRecommendationScreen({super.key, this.embedInDashboard = false});

  @override
  ConsumerState<OverallRecommendationScreen> createState() =>
      _OverallRecommendationScreenState();
}

class _OverallRecommendationScreenState
    extends ConsumerState<OverallRecommendationScreen> {
  bool _isLoadingSeasonal = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSeasonalData());
  }

  Future<void> _ensureSeasonalData() async {
    final state = ref.read(seasonalTrendsProvider);
    if (state.prediction != null) return;
    if (!mounted) return;
    setState(() => _isLoadingSeasonal = true);
    try {
      await ref.read(seasonalTrendsProvider.notifier).loadPredictions(
            region: 'Dubai',
            season: _currentSeason(),
            month: DateTime.now().month,
          );
    } catch (_) {}
    if (mounted) setState(() => _isLoadingSeasonal = false);
  }

  String _currentSeason() {
    final m = DateTime.now().month;
    if (m >= 3 && m <= 5) return 'Spring';
    if (m >= 6 && m <= 8) return 'Summer';
    if (m >= 9 && m <= 11) return 'Autumn';
    return 'Winter';
  }

  String _buildOverallParagraph(
    List<PlanningRecommendation> seasonalRecs,
    MaterialForecast? materialForecast,
  ) {
    final parts = <String>[
      'Based on Inventory Management, Seasonal Trends, and Material Forecasting: ',
    ];

    if (seasonalRecs.isNotEmpty) {
      final seasonalText = seasonalRecs
          .map((r) => r.description)
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      parts.add(seasonalText);
    }

    if (materialForecast != null) {
      parts.add(
        'For material ${materialForecast.materialCode} (${materialForecast.materialName}), '
        'the recommendation is to ${materialForecast.recommendation}: '
        '${materialForecast.recommendationReason}',
      );
    } else {
      parts.add(
        'Use Material Forecasting to analyze your material codes and get stock or do-not-stock recommendations based on procurement patterns.',
      );
    }

    parts.add(
      'Inventory management insights will be included in this overall recommendation once that feature is available.',
    );

    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final seasonalState = ref.watch(seasonalTrendsProvider);
    final materialState = ref.watch(materialForecastProvider);

    final seasonalRecs = seasonalState.prediction == null
        ? <PlanningRecommendation>[]
        : generateSeasonalRecommendations(seasonalState.prediction!);
    final isLoading = seasonalState.isLoading || _isLoadingSeasonal;

    final paragraph = _buildOverallParagraph(
      seasonalRecs,
      materialState.forecast,
    );

    return Scaffold(
      backgroundColor: AppTheme.dashboardBackground,
      appBar: AppBar(
        elevation: 0,
        leading: widget.embedInDashboard
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.iconGraphGreen, AppTheme.primaryGreenLight],
            ),
          ),
        ),
        title: const Text(
          'Overall Recommendation',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _ensureSeasonalData,
        child: SingleChildScrollView(
          padding: ResponsiveHelper.responsivePadding(context),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      paragraph,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppTheme.dashboardText,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
