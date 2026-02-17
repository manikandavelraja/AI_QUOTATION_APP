import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive_helper.dart';
import '../../data/services/vbelt_prediction_service.dart';
import '../providers/seasonal_trends_provider.dart';

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
  int _selectedMonth = DateTime.now().month;
  bool _isLoading = false;
  String? _sustainabilityInsight;

  final List<String> _regions = ['Dubai', 'Germany', 'India'];
  final List<String> _seasons = ['Spring', 'Summer', 'Autumn', 'Winter'];
  final List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  @override
  void initState() {
    super.initState();
    _loadPredictions();
  }

  Future<void> _loadPredictions() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(seasonalTrendsProvider.notifier).loadPredictions(
            region: _selectedRegion,
            season: _selectedSeason,
            month: _selectedMonth,
          );
      await _generateSustainabilityInsight();
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
      final insight = await VBeltPredictionService.generateSustainabilityInsight(
        region: _selectedRegion,
        season: _selectedSeason,
        month: _selectedMonth,
        predictedDemand: state.prediction!.predictedDemand,
        carbonFootprint: state.prediction!.carbonFootprint,
        sustainabilityScore: state.prediction!.sustainabilityScore,
        language: context.locale.languageCode,
      );
      setState(() => _sustainabilityInsight = insight);
    } catch (e) {
      debugPrint('Error generating insight: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.read(seasonalTrendsProvider);
    final isMobile = ResponsiveHelper.isMobile(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
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
                      _buildConfidenceGauges(context, state.prediction!),
                      const SizedBox(height: 24),
                      _buildRegionalMap(context),
                      const SizedBox(height: 24),
                      if (_sustainabilityInsight != null)
                        _buildSustainabilityInsight(context),
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
          colors: [AppTheme.primaryGreen, AppTheme.primaryGreenLight],
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
                  'Qumarionix GreenFlow',
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
                  const SizedBox(height: 16),
                  _buildMonthSelector(context),
                ],
              )
            : Row(
                children: [
                  Expanded(child: _buildRegionSelector(context)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildSeasonSelector(context)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildMonthSelector(context)),
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
        return DropdownMenuItem(
          value: region,
          child: Text(region),
        );
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
        return DropdownMenuItem(
          value: season,
          child: Text(season),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() => _selectedSeason = value);
          _loadPredictions();
        }
      },
    );
  }

  Widget _buildMonthSelector(BuildContext context) {
    return DropdownButtonFormField<int>(
      value: _selectedMonth,
      decoration: const InputDecoration(
        labelText: 'Month',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.calendar_today),
      ),
      items: List.generate(12, (index) {
        final month = index + 1;
        return DropdownMenuItem(
          value: month,
          child: Text(_months[month - 1]),
        );
      }),
      onChanged: (value) {
        if (value != null) {
          setState(() => _selectedMonth = value);
          _loadPredictions();
        }
      },
    );
  }

  Widget _buildKPICards(BuildContext context, PredictionResult prediction) {
    return Row(
      children: [
        Expanded(
          child: _buildKPICard(
            context,
            'Predicted Demand',
            '${prediction.predictedDemand.toStringAsFixed(0)} units',
            Icons.inventory_2,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKPICard(
            context,
            'Carbon Footprint',
            '${prediction.carbonFootprint.toStringAsFixed(2)} kg CO₂',
            Icons.eco,
            Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKPICard(
            context,
            'Sustainability Score',
            '${prediction.sustainabilityScore.toStringAsFixed(0)}/100',
            Icons.star,
            AppTheme.primaryGreen,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKPICard(
            context,
            'AI Confidence',
            '${(prediction.confidence * 100).toStringAsFixed(0)}%',
            Icons.psychology,
            Colors.purple,
          ),
        ),
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
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripleBottomLineChart(
      BuildContext context, PredictionResult prediction) {
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
                          final labels = ['Profit', 'Waste Reduction', 'Order Accuracy'];
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

  Widget _buildConfidenceGauges(
      BuildContext context, PredictionResult prediction) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI Confidence & ESG Gauges',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildGauge(
                    'AI Confidence',
                    prediction.confidence * 100,
                    Colors.purple,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildGauge(
                    'Sustainability Score',
                    prediction.sustainabilityScore,
                    AppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGauge(String label, double value, Color color) {
    return Column(
      children: [
        SizedBox(
          height: 150,
          width: 150,
          child: CircularProgressIndicator(
            value: value / 100,
            strokeWidth: 12,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        Text(
          '${value.toStringAsFixed(0)}%',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildRegionalMap(BuildContext context) {
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
              child: Row(
                children: _regions.map((region) {
                  final isSelected = region == _selectedRegion;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedRegion = region);
                        _loadPredictions();
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryGreen.withOpacity(0.2)
                              : Colors.grey[200],
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primaryGreen
                                : Colors.grey[300]!,
                            width: isSelected ? 3 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 48,
                              color: isSelected
                                  ? AppTheme.primaryGreen
                                  : Colors.grey[600],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              region,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? AppTheme.primaryGreen
                                    : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildRegionAlerts(region),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
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

  Widget _buildSustainabilityInsight(BuildContext context) {
    return Card(
      color: AppTheme.primaryGreen.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb, color: AppTheme.primaryGreen),
                const SizedBox(width: 8),
                const Text(
                  'Reflexive AI Sustainability Insight',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryGreen,
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

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.trending_up, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No Predictions Available',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Select region, season, and month to generate predictions',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

