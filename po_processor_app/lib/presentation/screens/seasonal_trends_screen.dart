import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive_helper.dart';
import '../../data/services/vbelt_prediction_service.dart';
import '../providers/seasonal_trends_provider.dart';
import '../utils/planning_recommendations_helper.dart';

/// Qumarionix GreenFlow - Seasonal Trends & V-Belt Predictor
/// Enterprise-grade ESG-driven supply chain command center
class SeasonalTrendsScreen extends ConsumerStatefulWidget {
  const SeasonalTrendsScreen({super.key});

  @override
  ConsumerState<SeasonalTrendsScreen> createState() =>
      _SeasonalTrendsScreenState();
}

class _SeasonalTrendsScreenState extends ConsumerState<SeasonalTrendsScreen> {
  String _selectedRegion = 'Dubai';
  String _selectedSeason = 'Spring';
  bool _isLoading = false;
  String? _sustainabilityInsight;
  List<PlanningRecommendation> _recommendations = [];

  final List<String> _regions = ['Dubai', 'Germany', 'India'];
  final List<String> _seasons = ['Spring', 'Summer', 'Autumn', 'Winter'];

  @override
  void initState() {
    super.initState();
    // Delay provider modification until after the widget tree is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPredictions();
    });
  }

  Future<void> _loadPredictions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Use current month as default for predictions
      final currentMonth = DateTime.now().month;
      await ref
          .read(seasonalTrendsProvider.notifier)
          .loadPredictions(
            region: _selectedRegion,
            season: _selectedSeason,
            month: currentMonth,
          );
      await _generateSustainabilityInsight();
      _generateRecommendations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading predictions: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _generateSustainabilityInsight() async {
    final state = ref.read(seasonalTrendsProvider);
    if (state.prediction == null) return;

    try {
      final insight =
          await VBeltPredictionService.generateSustainabilityInsight(
            region: _selectedRegion,
            season: _selectedSeason,
            month: DateTime.now().month,
            predictedDemand: state.prediction!.predictedDemand,
            carbonFootprint: state.prediction!.carbonFootprint,
            sustainabilityScore: state.prediction!.sustainabilityScore,
            language: context.locale.languageCode,
          );
      if (mounted &&
          insight.isNotEmpty &&
          !insight.contains('temporarily unavailable') &&
          !insight.contains('Unable to generate')) {
        setState(() => _sustainabilityInsight = insight);
      } else if (mounted) {
        // Generate a fallback insight if API fails
        setState(() {
          _sustainabilityInsight = _generateFallbackInsight(state.prediction!);
        });
      }
    } catch (e) {
      debugPrint('Error generating insight: $e');
      if (mounted && state.prediction != null) {
        setState(() {
          _sustainabilityInsight = _generateFallbackInsight(state.prediction!);
        });
      }
    }
  }

  String _generateFallbackInsight(PredictionResult prediction) {
    final weather = prediction.weatherData;
    final carbonPerUnit =
        prediction.carbonFootprint / prediction.predictedDemand;

    StringBuffer insight = StringBuffer();
    insight.writeln(
      'Based on the current prediction for $_selectedRegion during $_selectedSeason:',
    );
    insight.writeln('');
    insight.writeln(
      'The predicted demand of ${prediction.predictedDemand.toStringAsFixed(0)} units '
      'will result in a carbon footprint of ${prediction.carbonFootprint.toStringAsFixed(2)} kg CO₂ '
      '(${carbonPerUnit.toStringAsFixed(2)} kg per unit). ',
    );

    if (carbonPerUnit > 2.5) {
      insight.writeln(
        'To reduce environmental impact, consider sourcing from local suppliers or using '
        'eco-friendly transportation methods.',
      );
    }

    if (weather.temperature > 40) {
      insight.writeln(
        'Given the extreme temperature of ${weather.temperature.toStringAsFixed(1)}°C, '
        'V-belts may experience accelerated degradation. Consider heat-resistant variants '
        'and climate-controlled storage.',
      );
    }

    insight.writeln(
      'Optimize inventory management to reduce waste and improve sustainability metrics.',
    );

    return insight.toString();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.read(seasonalTrendsProvider);
    final isMobile = ResponsiveHelper.isMobile(context);

    return Scaffold(
      backgroundColor: AppTheme.dashboardBackground,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadPredictions,
              child: SingleChildScrollView(
                padding: ResponsiveHelper.responsivePadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 24),
                    _buildFilters(context, isMobile),
                    const SizedBox(height: 24),
                    if (state.prediction != null) ...[
                      _buildKPICards(context, state.prediction!),
                      const SizedBox(height: 24),
                      _buildTripleBottomLineChart(context, state.prediction!),
                      const SizedBox(height: 24),
                      _buildRegionalMap(context),
                      const SizedBox(height: 24),
                      if (_sustainabilityInsight != null)
                        _buildSustainabilityInsight(context),
                      const SizedBox(height: 24),
                      if (_recommendations.isNotEmpty)
                        _buildRecommendations(context, state.prediction!),
                    ] else
                      _buildEmptyState(context),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.iconGraphGreen, AppTheme.primaryGreenLight],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.trending_up, color: Colors.white, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Seasonal Trends Analysis',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ESG-Driven V-Belt Predictor & Seasonal Trends',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context, bool isMobile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: isMobile
            ? Column(
                children: [
                  _buildRegionSelector(context),
                  const SizedBox(height: 16),
                  _buildSeasonSelector(context),
                ],
              )
            : Row(
                children: [
                  Expanded(child: _buildRegionSelector(context)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildSeasonSelector(context)),
                ],
              ),
      ),
    );
  }

  Widget _buildRegionSelector(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: _selectedRegion,
      decoration: const InputDecoration(
        labelText: 'Region',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.location_on),
      ),
      items: _regions.map((region) {
        return DropdownMenuItem(value: region, child: Text(region));
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() => _selectedRegion = value);
          _loadPredictions();
        }
      },
    );
  }

  Widget _buildSeasonSelector(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: _selectedSeason,
      decoration: const InputDecoration(
        labelText: 'Season',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.wb_sunny),
      ),
      items: _seasons.map((season) {
        return DropdownMenuItem(value: season, child: Text(season));
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() => _selectedSeason = value);
          _loadPredictions();
        }
      },
    );
  }

  Widget _buildKPICards(BuildContext context, PredictionResult prediction) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final cards = [
      _buildKPICard(
        context,
        'Predicted Demand',
        '${prediction.predictedDemand.toStringAsFixed(0)} units',
        Icons.inventory_2,
        Colors.blue,
      ),
      _buildKPICard(
        context,
        'Carbon Footprint',
        '${prediction.carbonFootprint.toStringAsFixed(2)} kg CO₂',
        Icons.eco,
        Colors.green,
      ),
      _buildKPICard(
        context,
        'AI Confidence',
        '${(prediction.confidence * 100).toStringAsFixed(0)}%',
        Icons.psychology,
        Colors.purple,
      ),
    ];
    if (isMobile) {
      return Column(
        children: [
          cards[0],
          const SizedBox(height: 12),
          cards[1],
          const SizedBox(height: 12),
          cards[2],
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 12),
        Expanded(child: cards[1]),
        const SizedBox(width: 12),
        Expanded(child: cards[2]),
      ],
    );
  }

  Widget _buildKPICard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final isMobile = ResponsiveHelper.isMobile(context);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: isMobile ? 14 : 12,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripleBottomLineChart(
    BuildContext context,
    PredictionResult prediction,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Triple-Bottom-Line Analysis',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 100,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          final labels = [
                            'Profit',
                            'Waste Reduction',
                            'Order Accuracy',
                          ];
                          if (index >= 0 && index < labels.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                labels[index],
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: prediction.profitScore,
                          color: Colors.blue,
                          width: 20,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: prediction.wasteReductionScore,
                          color: Colors.green,
                          width: 20,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 2,
                      barRods: [
                        BarChartRodData(
                          toY: prediction.orderAccuracyScore,
                          color: Colors.orange,
                          width: 20,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegionalMap(BuildContext context) {
    final state = ref.read(seasonalTrendsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Regional Weather & Demand Heatmap',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 400,
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.iconGraphGreen.withOpacity(0.1),
                  border: Border.all(color: AppTheme.iconGraphGreen, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 64,
                      color: AppTheme.iconGraphGreen,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _selectedRegion,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.iconGraphGreen,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildRegionAlerts(_selectedRegion),
                    const SizedBox(height: 24),
                    if (state.prediction != null)
                      _buildRegionDetails(state.prediction!),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegionAlerts(String region) {
    String alert = '';
    IconData icon = Icons.info;
    Color color = Colors.blue;

    switch (region) {
      case 'Dubai':
        alert = 'Heat Alert: >40°C\nHigh Waste Risk';
        icon = Icons.warning;
        color = Colors.orange;
        break;
      case 'Germany':
        alert = 'Humidity/Cold\nBrittleness Alert';
        icon = Icons.ac_unit;
        color = Colors.blue;
        break;
      case 'India':
        alert = 'Monsoon Demand\nSpikes Expected';
        icon = Icons.water_drop;
        color = Colors.cyan;
        break;
    }

    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          alert,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildRegionDetails(PredictionResult prediction) {
    final weather = prediction.weatherData;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildWeatherInfo(
                'Temperature',
                '${weather.temperature.toStringAsFixed(1)}°C',
                Icons.thermostat,
              ),
              _buildWeatherInfo(
                'Humidity',
                '${weather.humidity.toStringAsFixed(0)}%',
                Icons.water_drop,
              ),
              _buildWeatherInfo(
                'Condition',
                weather.condition,
                Icons.wb_cloudy,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherInfo(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.iconGraphGreen, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppTheme.iconGraphGreen,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _buildSustainabilityInsight(BuildContext context) {
    return Card(
      color: AppTheme.iconGraphGreen.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb, color: AppTheme.iconGraphGreen),
                const SizedBox(width: 8),
                const Text(
                  'Sustainability Insight',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.iconGraphGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _sustainabilityInsight ?? '',
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  void _generateRecommendations() {
    final state = ref.read(seasonalTrendsProvider);
    if (state.prediction == null) {
      setState(() => _recommendations = []);
      return;
    }
    setState(() {
      _recommendations = generateSeasonalRecommendations(state.prediction!);
    });
  }

  Widget _buildRecommendations(
    BuildContext context,
    PredictionResult prediction,
  ) {
    if (_recommendations.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline,
                  color: AppTheme.iconGraphGreen,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Intelligence Recommendations',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.iconGraphGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Based on your current prediction details',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            ..._recommendations.map((rec) => _buildRecommendationCard(rec)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationCard(PlanningRecommendation recommendation) {
    Color priorityColor;
    switch (recommendation.priority) {
      case 'High':
        priorityColor = Colors.red;
        break;
      case 'Medium':
        priorityColor = Colors.orange;
        break;
      case 'Low':
        priorityColor = Colors.green;
        break;
      default:
        priorityColor = AppTheme.textSecondary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: recommendation.color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
        color: recommendation.color.withOpacity(0.05),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: recommendation.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                recommendation.icon,
                color: recommendation.color,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          recommendation.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: recommendation.color,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: priorityColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          recommendation.priority,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: priorityColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    recommendation.category,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    recommendation.description,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.trending_up, size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          Text(
            'No Predictions Available',
            style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Select region, season, and month to generate predictions',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

