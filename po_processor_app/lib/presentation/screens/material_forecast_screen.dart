import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/material_forecast_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/material_forecast.dart';
import '../../data/services/test_data_generator.dart';
import '../providers/po_provider.dart';

class MaterialForecastScreen extends ConsumerStatefulWidget {
  const MaterialForecastScreen({super.key});

  @override
  ConsumerState<MaterialForecastScreen> createState() =>
      _MaterialForecastScreenState();
}

class _MaterialForecastScreenState
    extends ConsumerState<MaterialForecastScreen> {
  final TextEditingController _materialCodeController = TextEditingController();
  final FocusNode _materialCodeFocusNode = FocusNode();
  final TestDataGenerator _testDataGenerator = TestDataGenerator();
  bool _isGeneratingTestData = false;

  @override
  void dispose() {
    _materialCodeController.dispose();
    _materialCodeFocusNode.dispose();
    super.dispose();
  }

  void _analyzeMaterial() {
    final materialCode = _materialCodeController.text.trim();
    debugPrint('🔍 [Material Forecast] Analyze button clicked');
    debugPrint('🔍 [Material Forecast] Material Code entered: "$materialCode"');
    if (materialCode.isNotEmpty) {
      debugPrint(
        '🔍 [Material Forecast] Calling analyzeMaterial with code: "$materialCode"',
      );
      ref.read(materialForecastProvider.notifier).analyzeMaterial(materialCode);
    } else {
      debugPrint(
        '⚠️ [Material Forecast] Material code is empty, not analyzing',
      );
    }
  }

  Future<void> _generateTestData() async {
    setState(() {
      _isGeneratingTestData = true;
    });

    try {
      await _testDataGenerator.generateTestPurchaseOrders();

      // Refresh PO list
      ref.read(poProvider.notifier).loadPurchaseOrders();

      // Refresh available material codes
      await ref.read(materialForecastProvider.notifier).reloadMaterialCodes();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Test purchase orders generated successfully!'),
            backgroundColor: AppTheme.successGreen,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error generating test data: $e'),
            backgroundColor: AppTheme.errorRed,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingTestData = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final forecastState = ref.watch(materialForecastProvider);
    final availableCodes = forecastState.availableMaterialCodes;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.primaryGreen, AppTheme.primaryGreenLight],
            ),
          ),
        ),
        title: const Text(
          'Forecast & Insights',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search Section
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter Material Code',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _materialCodeController,
                            focusNode: _materialCodeFocusNode,
                            decoration: InputDecoration(
                              labelText: 'Material Code',
                              hintText: 'e.g., MAT-001',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: availableCodes.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.arrow_drop_down),
                                      onPressed: () {
                                        _showMaterialCodePicker(
                                          context,
                                          availableCodes,
                                        );
                                      },
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onSubmitted: (_) => _analyzeMaterial(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: forecastState.isLoading
                              ? null
                              : _analyzeMaterial,
                          icon: forecastState.isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.analytics),
                          label: const Text('Analyze'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Test Data Generation Button
                    OutlinedButton.icon(
                      onPressed: _isGeneratingTestData
                          ? null
                          : _generateTestData,
                      icon: _isGeneratingTestData
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.science),
                      label: Text(
                        _isGeneratingTestData
                            ? 'Generating Test Data...'
                            : 'Generate Test Purchase Orders',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        side: const BorderSide(color: AppTheme.primaryGreen),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Generate test POs for: 1069683 (Water Tap), 1069685 (Bearing), 1069687 (Timing Belt), 1069689 (Filter), 1069680 (Lubricant)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Error Message
            if (forecastState.error != null)
              Card(
                color: AppTheme.errorRed.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.errorRed),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          forecastState.error!,
                          style: const TextStyle(color: AppTheme.errorRed),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Analysis Results
            if (forecastState.forecast != null) ...[
              const SizedBox(height: 16),
              _buildAnalysisResults(forecastState.forecast!),
            ],

            // Empty State
            if (!forecastState.isLoading &&
                forecastState.forecast == null &&
                forecastState.error == null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(48.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Enter a Material Code to analyze',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The system will analyze procurement patterns and provide inventory recommendations',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
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

  void _showMaterialCodePicker(BuildContext context, List<String> codes) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Select Material Code',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: codes.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(codes[index]),
                    onTap: () {
                      _materialCodeController.text = codes[index];
                      Navigator.pop(context);
                      _analyzeMaterial();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisResults(MaterialForecast forecast) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Recommendation Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: forecast.recommendation == 'Stock'
                    ? [
                        AppTheme.successGreen.withOpacity(0.1),
                        AppTheme.successGreen.withOpacity(0.05),
                      ]
                    : [
                        AppTheme.warningOrange.withOpacity(0.1),
                        AppTheme.warningOrange.withOpacity(0.05),
                      ],
              ),
            ),
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      forecast.recommendation == 'Stock'
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: forecast.recommendation == 'Stock'
                          ? AppTheme.successGreen
                          : AppTheme.warningOrange,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recommendation: ${forecast.recommendation}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: forecast.recommendation == 'Stock'
                                  ? AppTheme.successGreen
                                  : AppTheme.warningOrange,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            forecast.recommendationReason,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Summary Statistics
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Average Lead Time',
                '${forecast.averageLeadTimeDays.toStringAsFixed(1)} days',
                Icons.schedule,
                AppTheme.infoBlue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Consumption Rate',
                '${forecast.consumptionRatePerMonth.toStringAsFixed(1)} units/month',
                Icons.trending_up,
                AppTheme.primaryGreen,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Purchase Count (12M)',
                '${forecast.purchaseCountLast12Months}',
                Icons.shopping_cart,
                AppTheme.secondaryGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Total Quantity (12M)',
                '${forecast.totalQuantityLast12Months.toStringAsFixed(1)} ${forecast.purchaseHistory.isNotEmpty ? forecast.purchaseHistory.first.unit : ""}',
                Icons.inventory,
                AppTheme.accentGreen,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Avg Days Between Purchases',
                '${forecast.averageDaysBetweenPurchases.toStringAsFixed(1)} days',
                Icons.calendar_today,
                AppTheme.primaryGreenDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Consistency Score',
                '${(forecast.purchaseFrequencyConsistency * 100).toStringAsFixed(0)}%',
                Icons.insights,
                AppTheme.infoBlue,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Predicted Next Order Date
        if (forecast.predictedNextOrderDate != null)
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(
                    Icons.event,
                    color: AppTheme.primaryGreen,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Predicted Next Order Date',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat(
                            'MMMM dd, yyyy',
                          ).format(forecast.predictedNextOrderDate!),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Based on historical purchase intervals',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 16),

        // Purchase History Chart
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Purchase History (Last 12 Months)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: _buildPurchaseHistoryChart(forecast),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Purchase History Table
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Purchase History Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildPurchaseHistoryTable(forecast),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseHistoryChart(MaterialForecast forecast) {
    if (forecast.purchaseHistory.isEmpty) {
      return const Center(child: Text('No purchase history data available'));
    }

    final sortedHistory = List<PurchaseEvent>.from(forecast.purchaseHistory)
      ..sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));

    final spots = sortedHistory.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.quantity);
    }).toList();

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                if (value.toInt() < sortedHistory.length) {
                  final date = sortedHistory[value.toInt()].purchaseDate;
                  return Text(
                    DateFormat('MMM').format(date),
                    style: const TextStyle(fontSize: 10),
                  );
                }
                return const Text('');
              },
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.primaryGreen,
            barWidth: 3,
            dotData: FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.primaryGreen.withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseHistoryTable(MaterialForecast forecast) {
    if (forecast.purchaseHistory.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text('No purchase history available'),
        ),
      );
    }

    final sortedHistory = List<PurchaseEvent>.from(forecast.purchaseHistory)
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('PO Number')),
          DataColumn(label: Text('Quantity')),
          DataColumn(label: Text('Unit')),
          DataColumn(label: Text('Lead Time')),
        ],
        rows: sortedHistory.map((purchase) {
          return DataRow(
            cells: [
              DataCell(
                Text(DateFormat('MMM dd, yyyy').format(purchase.purchaseDate)),
              ),
              DataCell(Text(purchase.poNumber)),
              DataCell(Text(purchase.quantity.toStringAsFixed(2))),
              DataCell(Text(purchase.unit)),
              DataCell(
                Text(
                  purchase.leadTimeDays != null
                      ? '${purchase.leadTimeDays} days'
                      : 'N/A',
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
