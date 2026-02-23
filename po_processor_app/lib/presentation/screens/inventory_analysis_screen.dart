import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive_helper.dart';

// ---------------------------------------------------------------------------
// Models & mock data
// ---------------------------------------------------------------------------

/// Single material row: Material Name, Current Stock, Predicted Demand, Delta, Status
class InventoryMaterialItem {
  final String materialName;
  final String materialCode;
  final double currentStock;
  final double predictedDemand;
  final double delta;
  final String status;

  const InventoryMaterialItem({
    required this.materialName,
    required this.materialCode,
    required this.currentStock,
    required this.predictedDemand,
    required this.delta,
    required this.status,
  });
}

/// Past month trend point for chart (consumption per week → predicted demand)
class InventoryTrendPoint {
  final String label;
  final double consumption;

  const InventoryTrendPoint({required this.label, required this.consumption});
}

/// True Inventory Health: score 0–100 and label (e.g. "27% At Risk").
/// Uses fixed modifiers: Dead Stock 85 units, Wastage 2.2%.
class InventoryHealthResult {
  final double healthScore;
  final String healthLabel;

  const InventoryHealthResult({
    required this.healthScore,
    required this.healthLabel,
  });
}

/// One recommendation line
class InventoryRecommendation {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  const InventoryRecommendation({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}

// ---------------------------------------------------------------------------
// Mock data: materials + fixed modifiers
// ---------------------------------------------------------------------------

class InventoryMockData {
  /// Searchable materials: Water Tap, V-Belt, Gloves, Lubricants
  static const List<InventoryMaterialItem> materials = [
    InventoryMaterialItem(
      materialName: 'Water Tap',
      materialCode: 'WT-001',
      currentStock: 1280,
      predictedDemand: 1870,
      delta: -590,
      status: 'Understock',
    ),
    InventoryMaterialItem(
      materialName: 'V-Belt',
      materialCode: 'VB-002',
      currentStock: 450,
      predictedDemand: 300,
      delta: 150,
      status: 'Surplus',
    ),
    InventoryMaterialItem(
      materialName: 'Gloves',
      materialCode: 'GL-003',
      currentStock: 320,
      predictedDemand: 280,
      delta: 40,
      status: 'Surplus',
    ),
    InventoryMaterialItem(
      materialName: 'Lubricants',
      materialCode: 'LB-004',
      currentStock: 95,
      predictedDemand: 120,
      delta: -25,
      status: 'Understock',
    ),
  ];

  /// Fixed negative modifiers for True Inventory Health (as per requirement)
  static const double deadStockUnits = 85;
  static const double wastagePercent = 2.2;

  /// Past month weekly trend for a material (used to derive predicted demand in UI)
  static List<InventoryTrendPoint> pastMonthTrendFor(String materialCode) {
    try {
      final m = materials.firstWhere((e) => e.materialCode == materialCode);
      return _defaultTrend(m.predictedDemand);
    } catch (_) {
      return _defaultTrend(100);
    }
  }

  static List<InventoryTrendPoint> _defaultTrend(double monthlyTotal) {
    const labels = ['Week 1', 'Week 2', 'Week 3', 'Week 4'];
    final perWeek = monthlyTotal / 4;
    return List.generate(4, (i) => InventoryTrendPoint(
      label: labels[i],
      consumption: perWeek * (0.9 + (i * 0.05)),
    ));
  }

  /// True Inventory Health: compare current stock vs predicted demand, apply
  /// dead stock (85 units) and wastage (2.2%) as negative modifiers.
  static InventoryHealthResult computeHealth(InventoryMaterialItem material) {
    final demand = material.predictedDemand > 0 ? material.predictedDemand : 1.0;
    final delta = material.delta;

    double baseScore = 50;
    if (delta > 0) {
      final surplusRatio = (delta / demand).clamp(0.0, 0.6);
      baseScore = 50 + (surplusRatio * 50);
    } else {
      final deficitRatio = (-delta / demand).clamp(0.0, 1.0);
      baseScore = 50 - (deficitRatio * 50);
    }
    baseScore = baseScore.clamp(0.0, 100.0);

    // Negative modifiers: dead stock 85 units, wastage 2.2%
    final deadPenalty = (deadStockUnits / demand).clamp(0.0, 1.0) * 25;
    final wastePenalty = (wastagePercent / 10).clamp(0.0, 1.0) * 25;
    final healthScore = (baseScore - deadPenalty - wastePenalty).clamp(0.0, 100.0).toDouble();

    String healthLabel;
    if (healthScore >= 75) {
      healthLabel = 'Healthy';
    } else if (healthScore >= 50) {
      healthLabel = 'Moderate';
    } else if (healthScore >= 25) {
      healthLabel = 'At Risk';
    } else {
      healthLabel = 'Critical';
    }

    return InventoryHealthResult(healthScore: healthScore, healthLabel: healthLabel);
  }

  /// Recommendations: if Delta negative → increase stock; if dead stock high → clear dead stock.
  static List<InventoryRecommendation> getRecommendations(
    InventoryMaterialItem material,
    InventoryHealthResult health,
  ) {
    final recs = <InventoryRecommendation>[];

    if (material.delta < 0) {
      recs.add(InventoryRecommendation(
        title: 'Increase stock to meet demand',
        description:
            'Current stock (${material.currentStock.toStringAsFixed(0)} units) is below predicted demand (${material.predictedDemand.toStringAsFixed(0)} units). Delta = ${material.delta.toStringAsFixed(0)}. Place orders to avoid stockouts and consider a 10–15% safety buffer.',
        icon: Icons.arrow_upward,
        color: AppTheme.warningOrange,
      ));
    }

    if (deadStockUnits > 50) {
      recs.add(InventoryRecommendation(
        title: 'Clear dead stock',
        description:
            '${deadStockUnits.toStringAsFixed(0)} units are classified as dead stock. Run a clearance or write-off to free space and improve inventory health.',
        icon: Icons.delete_sweep,
        color: AppTheme.errorRed,
      ));
    }

    if (recs.isEmpty) {
      recs.add(InventoryRecommendation(
        title: 'Monitor and maintain',
        description: 'Stock is aligned with demand. Keep monitoring trend data and reorder points.',
        icon: Icons.check_circle_outline,
        color: AppTheme.successGreen,
      ));
    }

    return recs;
  }
}

// ---------------------------------------------------------------------------
// Inventory Management Screen
// ---------------------------------------------------------------------------

class InventoryAnalysisScreen extends ConsumerStatefulWidget {
  const InventoryAnalysisScreen({super.key});

  @override
  ConsumerState<InventoryAnalysisScreen> createState() =>
      _InventoryAnalysisScreenState();
}

class _InventoryAnalysisScreenState extends ConsumerState<InventoryAnalysisScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _currentStockController = TextEditingController();

  List<InventoryMaterialItem> _filteredMaterials = InventoryMockData.materials;
  InventoryMaterialItem? _selectedMaterial;
  /// User-entered current stock per material code (after Save). Used for predicted analysis.
  final Map<String, double> _currentStockOverrides = {};

  @override
  void initState() {
    super.initState();
    _filteredMaterials = List.from(InventoryMockData.materials);
    _selectedMaterial = _filteredMaterials.isNotEmpty ? _filteredMaterials.first : null;
    _syncCurrentStockController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _currentStockController.dispose();
    super.dispose();
  }

  /// Effective material for analysis: uses saved override for current stock, recomputes delta & status.
  InventoryMaterialItem? _getEffectiveMaterial() {
    final m = _selectedMaterial;
    if (m == null) return null;
    final stock = _currentStockOverrides[m.materialCode] ?? m.currentStock;
    final delta = stock - m.predictedDemand;
    final status = delta < 0 ? 'Understock' : 'Surplus';
    return InventoryMaterialItem(
      materialName: m.materialName,
      materialCode: m.materialCode,
      currentStock: stock,
      predictedDemand: m.predictedDemand,
      delta: delta,
      status: status,
    );
  }

  void _syncCurrentStockController() {
    final effective = _getEffectiveMaterial();
    if (effective != null) {
      _currentStockController.text = effective.currentStock.toInt().toString();
    }
  }

  void _onSearchChanged(String value) {
    final q = value.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredMaterials = List.from(InventoryMockData.materials);
      } else {
        _filteredMaterials = InventoryMockData.materials
            .where((m) =>
                m.materialName.toLowerCase().contains(q) ||
                m.materialCode.toLowerCase().contains(q))
            .toList();
      }
      if (_filteredMaterials.isNotEmpty && !_filteredMaterials.contains(_selectedMaterial)) {
        _selectedMaterial = _filteredMaterials.first;
      } else if (_filteredMaterials.isEmpty) {
        _selectedMaterial = null;
      }
    });
  }

  void _selectMaterial(InventoryMaterialItem material) {
    setState(() {
      _selectedMaterial = material;
      _syncCurrentStockController();
    });
  }

  void _saveCurrentStock() {
    final m = _selectedMaterial;
    if (m == null) return;
    final text = _currentStockController.text.trim();
    final value = double.tryParse(text);
    if (value == null || value < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid positive number for current stock.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }
    setState(() {
      _currentStockOverrides[m.materialCode] = value;
      _syncCurrentStockController();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Current stock saved. Predicted analysis updated for ${m.materialName}.'),
        backgroundColor: AppTheme.successGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: SingleChildScrollView(
        padding: ResponsiveHelper.responsivePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 20),
            _buildSearchSection(context),
            const SizedBox(height: 20),
            if (_selectedMaterial != null) ...[
              _buildEditCurrentStockSection(context),
              const SizedBox(height: 20),
              _buildMetricCards(context, isMobile),
              const SizedBox(height: 20),
              _buildHealthGauge(context),
              const SizedBox(height: 20),
              _buildPastMonthTrendCard(context),
              const SizedBox(height: 20),
              _buildRecommendationSection(context),
            ] else
              _buildEmptyState(context),
          ],
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
          const Icon(Icons.inventory_2, color: Colors.white, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inventory Management',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Search by material code • Predicted demand from past month trend • Delta & True Inventory Health',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSection(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Search material',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'e.g. Water Tap, V-Belt, Gloves, Lubricants',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            if (_filteredMaterials.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _filteredMaterials.map((m) {
                  final isSelected = _selectedMaterial == m;
                  return FilterChip(
                    label: Text('${m.materialName} (${m.materialCode})'),
                    selected: isSelected,
                    onSelected: (_) => _selectMaterial(m),
                    selectedColor: AppTheme.primaryGreen.withOpacity(0.2),
                    checkmarkColor: AppTheme.primaryGreen,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Editable current stock field + Save; after Save, predicted analysis uses this value.
  Widget _buildEditCurrentStockSection(BuildContext context) {
    final m = _selectedMaterial!;
    final hasOverride = _currentStockOverrides.containsKey(m.materialCode);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit, color: AppTheme.primaryGreen, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Current stock',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (hasOverride) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text('Saved', style: TextStyle(fontSize: 11, color: AppTheme.successGreen)),
                    backgroundColor: AppTheme.successGreen.withOpacity(0.15),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Enter current stock for ${m.materialName} and tap Save to update predicted analysis (Delta, Health, Recommendations).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = ResponsiveHelper.isMobile(context);
                return isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _currentStockController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Current stock (units)',
                              hintText: 'e.g. ${m.currentStock.toInt()}',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              suffixText: 'units',
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _saveCurrentStock,
                            icon: const Icon(Icons.save, size: 20),
                            label: const Text('Save'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _currentStockController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Current stock (units)',
                                hintText: 'e.g. ${m.currentStock.toInt()}',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                suffixText: 'units',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _saveCurrentStock,
                            icon: const Icon(Icons.save, size: 20),
                            label: const Text('Save'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            ),
                          ),
                        ],
                      );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Dashboard-style cards: Material Name, Current Stock, Predicted Demand, Delta (Δ), Status
  Widget _buildMetricCards(BuildContext context, bool isMobile) {
    final m = _getEffectiveMaterial()!;
    final cardWidth = ResponsiveHelper.responsiveStatCardWidth(context);

    final items = [
      _StatCardItem('Material Name', m.materialName, Icons.category, AppTheme.primaryGreen),
      _StatCardItem('Current Stock', '${m.currentStock.toStringAsFixed(0)} units', Icons.inventory, Colors.blue),
      _StatCardItem('Predicted Demand', '${m.predictedDemand.toStringAsFixed(0)} units', Icons.trending_up, Colors.indigo),
      _StatCardItem('Delta (Δ)', '${m.delta >= 0 ? '+' : ''}${m.delta.toStringAsFixed(0)}', m.delta >= 0 ? Icons.add_circle : Icons.remove_circle, m.delta >= 0 ? AppTheme.successGreen : AppTheme.warningOrange),
      _StatCardItem('Status', m.status, Icons.info_outline, m.status == 'Understock' ? AppTheme.warningOrange : AppTheme.successGreen),
    ];

    return SizedBox(
      height: isMobile ? 200 : 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Container(
            width: cardWidth,
            margin: const EdgeInsets.only(right: 12),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      item.color.withOpacity(0.08),
                      item.color.withOpacity(0.02),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.icon, color: item.color, size: 28),
                    const SizedBox(height: 12),
                    Text(
                      item.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.value,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Inventory Health gauge: rich modern circular gauge with score and label
  Widget _buildHealthGauge(BuildContext context) {
    final effective = _getEffectiveMaterial();
    if (effective == null) return const SizedBox.shrink();
    final health = InventoryMockData.computeHealth(effective);
    final score = health.healthScore;
    final scoreClamped = (score / 100).clamp(0.0, 1.0);
    Color scoreColor = score >= 75
        ? AppTheme.successGreen
        : score >= 50
            ? AppTheme.warningOrange
            : score >= 25
                ? AppTheme.warningOrange
                : AppTheme.errorRed;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final trackColor = isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      padding: ResponsiveHelper.responsiveCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scoreColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.health_and_safety_outlined, size: 22, color: scoreColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'True Inventory Health',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dead stock (${InventoryMockData.deadStockUnits.toStringAsFixed(0)} units) and wastage (${InventoryMockData.wastagePercent.toStringAsFixed(1)}%) applied as negative modifiers.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = 160.0;
              final strokeWidth = 14.0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: size,
                    height: size,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Track
                        SizedBox(
                          width: size,
                          height: size,
                          child: CircularProgressIndicator(
                            value: 1,
                            strokeWidth: strokeWidth,
                            strokeCap: StrokeCap.round,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(trackColor),
                          ),
                        ),
                        // Value arc with gradient
                        SizedBox(
                          width: size,
                          height: size,
                          child: CircularProgressIndicator(
                            value: scoreClamped,
                            strokeWidth: strokeWidth,
                            strokeCap: StrokeCap.round,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                          ),
                        ),
                        // Center content
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${score.toStringAsFixed(0)}',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: scoreColor,
                                    letterSpacing: -0.5,
                                  ),
                            ),
                            Text(
                              '%',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: scoreColor,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: scoreColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: scoreColor.withOpacity(0.4)),
                              ),
                              child: Text(
                                health.healthLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: scoreColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${score.toStringAsFixed(0)}% ${health.healthLabel}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: scoreColor,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Based on current stock vs predicted demand for ${effective.materialName}, with dead stock and wastage reducing the score.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                                height: 1.4,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPastMonthTrendCard(BuildContext context) {
    if (_selectedMaterial == null) return const SizedBox.shrink();
    final trend = InventoryMockData.pastMonthTrendFor(_selectedMaterial!.materialCode);
    final maxConsumption = trend.fold<double>(0, (a, p) => a > p.consumption ? a : p.consumption);
    final maxY = (maxConsumption * 1.15).clamp(10.0, double.infinity);
    final minY = 0.0;
    final spots = trend.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.consumption)).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final textColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;
    final gridColor = isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade200;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.show_chart_rounded, size: 22, color: AppTheme.primaryGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Past month trend (weekly) → Predicted demand',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  drawHorizontalLine: true,
                  horizontalInterval: (maxY - minY) / 5,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: gridColor,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      interval: (maxY - minY) / 5,
                      getTitlesWidget: (value, meta) {
                        if (value == value.roundToDouble()) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              value.toInt().toString(),
                              style: TextStyle(
                                color: textColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i >= 0 && i < trend.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              trend[i].label,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (trend.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: AppTheme.primaryGreen,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                        radius: 4,
                        color: AppTheme.primaryGreen,
                        strokeWidth: 2,
                        strokeColor: isDark ? Colors.white24 : Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppTheme.primaryGreen.withOpacity(0.25),
                          AppTheme.primaryGreen.withOpacity(0.05),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 300),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationSection(BuildContext context) {
    final effective = _getEffectiveMaterial();
    if (effective == null) return const SizedBox.shrink();
    final health = InventoryMockData.computeHealth(effective);
    final recs = InventoryMockData.getRecommendations(effective, health);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recommendations',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        ...recs.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: r.color.withOpacity(0.4)),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: r.color.withOpacity(0.2),
                  child: Icon(r.icon, color: r.color, size: 24),
                ),
                title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(r.description, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No material found. Try "Water Tap", "V-Belt", "Gloves", or "Lubricants".',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCardItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  _StatCardItem(this.label, this.value, this.icon, this.color);
}
