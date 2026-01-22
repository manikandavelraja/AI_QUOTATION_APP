import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/po_provider.dart';
import '../providers/auth_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/purchase_order.dart';
import '../../domain/entities/customer_inquiry.dart';
import '../../data/services/email_service.dart';
import '../../data/services/pdf_service.dart';
import '../../data/services/gemini_ai_service.dart';
import '../providers/inquiry_provider.dart';
import 'package:file_picker/file_picker.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final _emailService = EmailService();
  final _pdfService = PDFService();
  final _aiService = GeminiAIService();
  bool _isFetchingInquiry = false;
  bool _isFetchingPO = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final poState = ref.watch(poProvider);
    final stats = poState.dashboardStats ?? {};
    final monthlyData = _getMonthlyStatistics(poState.purchaseOrders);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryGreen,
                  const Color(0xFF4CAF50),
              ],
            ),
          ),
        ),
        title: Text(
          'dashboard'.tr(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: () => context.push('/upload'),
            tooltip: 'upload_po'.tr(),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
            tooltip: 'settings'.tr(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              context.go('/login');
            },
            tooltip: 'logout'.tr(),
          ),
        ],
      ),
      body: poState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.read(poProvider.notifier).loadPurchaseOrders(),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWelcomeHeader(context),
                      const SizedBox(height: 24),
                      _buildStatsGrid(context, stats),
                      const SizedBox(height: 24),
                      _buildMonthlyUsageGraph(context, monthlyData),
                      const SizedBox(height: 24),
                      _buildExpiringAlerts(context, poState),
                      const SizedBox(height: 24),
                      _buildSustainabilityMetrics(context, stats),
                      const SizedBox(height: 24),
                      _buildQuickActions(context),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/upload'),
        backgroundColor: const Color(0xFF2E7D32),
        icon: const Icon(Icons.add),
        label: Text('upload_po'.tr()),
        elevation: 4,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        selectedItemColor: const Color(0xFF2E7D32),
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard),
            label: 'dashboard'.tr(),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.list),
            label: 'po_list'.tr(),
          ),
        ],
        onTap: (index) {
          if (index == 1) {
            context.push('/po-list');
          }
        },
      ),
    );
  }

  Widget _buildWelcomeHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryGreen.withOpacity(0.1),
            AppTheme.primaryGreenLight.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryGreen.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.trending_up,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'business_pulse'.tr(),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryGreen,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Real-time insights and analytics',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context, Map<String, dynamic> stats) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.3,
      children: [
        _buildStatCard(
          context,
          'today_purchase_orders'.tr(),
          '${stats['todayPOs'] ?? 0}',
          Icons.description,
          [Colors.blue.shade400, Colors.blue.shade600],
          Colors.blue.shade50,
        ),
        _buildStatCard(
          context,
          'total_po_value'.tr(),
          '₹${(stats['totalValue'] ?? 0).toStringAsFixed(0)}',
          Icons.attach_money,
          [Colors.green.shade400, Colors.green.shade600],
          Colors.green.shade50,
        ),
        _buildStatCard(
          context,
          'expiring_this_week'.tr(),
          '${stats['expiringThisWeek'] ?? 0}',
          Icons.warning,
          [Colors.orange.shade400, Colors.orange.shade600],
          Colors.orange.shade50,
        ),
        _buildStatCard(
          context,
          'total_pos'.tr(),
          '${stats['totalPOs'] ?? 0}',
          Icons.inventory,
          [Colors.purple.shade400, Colors.purple.shade600],
          Colors.purple.shade50,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    List<Color> gradientColors,
    Color backgroundColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 24, color: Colors.white),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Map<String, Map<String, dynamic>> _getMonthlyStatistics(List<PurchaseOrder> pos) {
    final now = DateTime.now();
    final Map<String, Map<String, dynamic>> monthlyData = {};
    
    // Get last 6 months
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      final monthName = DateFormat('MMM').format(month);
      
      final monthPOs = pos.where((po) {
        return po.poDate.year == month.year && po.poDate.month == month.month;
      }).toList();
      
      final monthValue = monthPOs.fold<double>(
        0,
        (sum, po) => sum + po.totalAmount,
      );
      
      monthlyData[monthKey] = {
        'name': monthName,
        'count': monthPOs.length,
        'value': monthValue,
      };
    }
    
    return monthlyData;
  }

  Widget _buildMonthlyUsageGraph(BuildContext context, Map<String, Map<String, dynamic>> monthlyData) {
    if (monthlyData.isEmpty) {
      return const SizedBox.shrink();
    }

    final spots = monthlyData.entries.toList();
    final maxValue = monthlyData.values.isEmpty
        ? 0.0
        : monthlyData.values
            .map((e) => e['value'] as double)
            .reduce((a, b) => a > b ? a : b);
    final maxCount = monthlyData.values.isEmpty
        ? 0
        : monthlyData.values
            .map((e) => e['count'] as int)
            .reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.bar_chart,
                  color: AppTheme.primaryGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly Usage Statistics',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      'PO count and value over time',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 250,
            child: Row(
              children: [
                // Value Chart (Bar Chart)
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Value (₹)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: maxValue > 0 ? maxValue * 1.2 : 10,
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                tooltipBgColor: AppTheme.primaryGreen,
                                tooltipRoundedRadius: 8,
                                tooltipPadding: const EdgeInsets.all(8),
                                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                  return BarTooltipItem(
                                    '₹${rod.toY.toStringAsFixed(0)}',
                                    const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                },
                              ),
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final index = value.toInt();
                                    if (index >= 0 && index < spots.length) {
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          spots[index].value['name'] as String,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      );
                                    }
                                    return const Text('');
                                  },
                                  reservedSize: 30,
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 50,
                                  getTitlesWidget: (value, meta) {
                                    final interval = maxValue > 0 ? (maxValue * 1.2) / 4 : 2.5;
                                    if (interval > 0 && value % interval < interval * 0.1) {
                                      return Text(
                                        '₹${(value / 1000).toStringAsFixed(0)}K',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
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
                            borderData: FlBorderData(show: false),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: maxValue > 0 ? (maxValue * 1.2) / 4 : 2.5,
                              getDrawingHorizontalLine: (value) {
                                return FlLine(
                                  color: Colors.grey.withOpacity(0.1),
                                  strokeWidth: 1,
                                );
                              },
                            ),
                            barGroups: spots.asMap().entries.map((entry) {
                              final index = entry.key;
                              final spot = entry.value;
                              return BarChartGroupData(
                                x: index,
                                barRods: [
                                  BarChartRodData(
                                    toY: spot.value['value'] as double,
                                    color: AppTheme.primaryGreen,
                                    width: 20,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Count Chart (Line Chart)
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PO Count',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: LineChart(
                          LineChartData(
                            maxY: maxCount > 0 ? maxCount * 1.2 : 10,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: maxCount > 0 ? (maxCount * 1.2) / 4 : 2.5,
                              getDrawingHorizontalLine: (value) {
                                return FlLine(
                                  color: Colors.grey.withOpacity(0.1),
                                  strokeWidth: 1,
                                );
                              },
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  getTitlesWidget: (value, meta) {
                                    final interval = maxCount > 0 ? (maxCount * 1.2) / 4 : 2.5;
                                    if (interval > 0 && value % interval < interval * 0.1) {
                                      return Text(
                                        value.toInt().toString(),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                      );
                                    }
                                    return const Text('');
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final index = value.toInt();
                                    if (index >= 0 && index < spots.length) {
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          spots[index].value['name'] as String,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      );
                                    }
                                    return const Text('');
                                  },
                                  reservedSize: 30,
                                ),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: spots.asMap().entries.map((entry) {
                                  return FlSpot(
                                    entry.key.toDouble(),
                                    (entry.value.value['count'] as int).toDouble(),
                                  );
                                }).toList(),
                                isCurved: true,
                                color: Colors.blue,
                                barWidth: 3,
                                isStrokeCapRound: true,
                                dotData: const FlDotData(show: true),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: Colors.blue.withOpacity(0.1),
                                ),
                              ),
                            ],
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                tooltipBgColor: Colors.blue,
                                tooltipRoundedRadius: 8,
                                tooltipPadding: const EdgeInsets.all(8),
                                getTooltipItems: (List<LineBarSpot> touchedSpots) {
                                  return touchedSpots.map((LineBarSpot touchedSpot) {
                                    return LineTooltipItem(
                                      '${touchedSpot.y.toInt()} POs',
                                      const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  }).toList();
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiringAlerts(BuildContext context, POState poState) {
    final expiringPOs = poState.expiringPOs;
    
    if (expiringPOs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.orange.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warning, color: Colors.orange, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'expiring_soon'.tr(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...expiringPOs.take(5).map((po) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.withOpacity(0.2),
                  ),
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.description, color: Colors.orange),
                  ),
                  title: Text(
                    po.poNumber,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(po.customerName),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        DateFormat('MMM dd').format(po.expiryDate),
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        DateFormat('yyyy').format(po.expiryDate),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  onTap: () => context.push('/po-detail/${po.id}'),
                ),
              )),
          if (expiringPOs.length > 5)
            Center(
              child: TextButton(
                onPressed: () => context.push('/po-list'),
                child: Text('view_all'.tr()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSustainabilityMetrics(BuildContext context, Map<String, dynamic> stats) {
    final totalPOs = stats['totalPOs'] ?? 0;
    final paperSaved = totalPOs * AppConstants.paperSavedPerPO;
    final carbonReduced = totalPOs * AppConstants.carbonFootprintPerPO;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.green.shade50,
            Colors.green.shade100.withOpacity(0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.green.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.eco, color: Colors.green, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'sustainability_metrics'.tr(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricItem(
                context,
                'paper_saved'.tr(),
                '${paperSaved.toStringAsFixed(1)} ${'sheets'.tr()}',
                Icons.description,
                Colors.green,
              ),
              _buildMetricItem(
                context,
                'carbon_footprint_reduced'.tr(),
                '${carbonReduced.toStringAsFixed(2)} ${'kg_co2'.tr()}',
                Icons.eco,
                Colors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.flash_on,
                  color: AppTheme.primaryGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'quick_actions'.tr(),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Modern Rich UI with consistent color scheme
          // Stage 1: Customer Inquiry
          _buildModernActionButton(
            context,
            'Customer Inquiries',
            Icons.question_answer,
            () => context.push('/inquiry-list'),
            subtitle: 'View all customer inquiries',
          ),
          const SizedBox(height: 12),
          _buildModernActionButton(
            context,
            _isFetchingInquiry ? 'Fetching Inquiries...' : 'Get Inquiry from Mail',
            Icons.email,
            _isFetchingInquiry ? () {} : _getInquiryFromMail,
            subtitle: 'Fetch inquiries from Gmail',
            isLoading: _isFetchingInquiry,
          ),
          const SizedBox(height: 12),
          // Stage 2: Quotation
          Row(
            children: [
              Expanded(
                child: _buildModernActionButton(
                  context,
                  'Quotations',
                  Icons.description,
                  () => context.push('/quotation-list'),
                  subtitle: 'View all quotations',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildModernActionButton(
                  context,
                  'Generate Quotation',
                  Icons.add_business,
                  _showGenerateQuotationDialog,
                  subtitle: 'Create new quotation',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Stage 3: Purchase Order
          Row(
            children: [
              Expanded(
                child: _buildModernActionButton(
                  context,
                  'upload_po'.tr(),
                  Icons.upload_file,
                  () => context.push('/upload'),
                  subtitle: 'Upload PO document',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildModernActionButton(
                  context,
                  _isFetchingPO ? 'Fetching POs...' : 'Get PO from Mail',
                  Icons.email,
                  _isFetchingPO ? () {} : _getPOFromMail,
                  subtitle: 'Fetch POs from Gmail',
                  isLoading: _isFetchingPO,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildModernActionButton(
            context,
            'po_list'.tr(),
            Icons.list,
            () => context.push('/po-list'),
            subtitle: 'View all purchase orders',
          ),
          const SizedBox(height: 12),
          // Stage 4: Supplier Orders
          _buildModernActionButton(
            context,
            'Supplier Orders',
            Icons.shopping_cart,
            () => context.push('/supplier-order-list'),
            subtitle: 'Manage supplier orders',
          ),
          const SizedBox(height: 12),
          // Stage 5: Delivery Documents
          _buildModernActionButton(
            context,
            'Delivery Documents',
            Icons.receipt_long,
            () => context.push('/delivery-document-list'),
            subtitle: 'Track deliveries',
          ),
        ],
      ),
    );
  }

  /// Modern action button with rich UI and consistent color scheme
  Widget _buildModernActionButton(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onPressed, {
    String? subtitle,
    bool isLoading = false,
  }) {
    // Use primary green theme for all buttons
    final primaryColor = AppTheme.primaryGreen;
    final secondaryColor = AppTheme.primaryGreenLight;
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor,
            secondaryColor,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white.withOpacity(0.8),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Future<void> _getInquiryFromMail() async {
    try {
      // Close any existing dialogs first to prevent stacking
      if (mounted) {
        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
      }
      
      setState(() => _isFetchingInquiry = true);

      // Show loading message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Accessing Gmail (kumarionix07@gmail.com) and fetching Customer Inquiry PDF...'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Automatically fetch emails via Gmail API
      // First time: Will prompt for Gmail sign-in (one-time)
      // After sign-in: Uses stored tokens automatically
      final emails = await _emailService.fetchInquiryEmails(maxResults: 10);

      if (emails.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No inquiry emails found in inbox'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() => _isFetchingInquiry = false);
        return;
      }

      // Automatically process the first email found (most recent)
      // If multiple emails, process the first one automatically
      final selectedEmail = emails.first;
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Found ${emails.length} inquiry email(s). Processing the most recent one...'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Process the selected email with PDF attachment
      final inquiryEmail = selectedEmail!;
      final pdfAttachment = inquiryEmail.attachments.firstWhere(
        (att) => att.name.toLowerCase().endsWith('.pdf') || 
                 att.name.toLowerCase().endsWith('.doc') ||
                 att.name.toLowerCase().endsWith('.docx'),
        orElse: () => throw Exception('No PDF or DOC attachment found in email'),
      );

      // Fetch attachment data if not already loaded
      Uint8List pdfData;
      if (pdfAttachment.data.isEmpty && pdfAttachment.attachmentId != null && pdfAttachment.messageId != null) {
        // Need to fetch attachment data from Gmail API
        pdfData = await _emailService.fetchAttachmentData(pdfAttachment.messageId!, pdfAttachment.attachmentId!);
      } else {
        pdfData = pdfAttachment.data;
      }

      if (pdfData.isEmpty) {
        throw Exception('Failed to fetch PDF attachment data from email');
      }

      // Extract inquiry data directly from PDF bytes (visual processing)
      CustomerInquiry inquiry;
      if (pdfAttachment.name.toLowerCase().endsWith('.pdf')) {
        inquiry = await _aiService.extractInquiryFromPDFBytes(pdfData, pdfAttachment.name);
      } else {
        throw Exception('DOC file processing not yet implemented. Please use PDF files.');
      }

      // Capture sender email from the email metadata
      final senderEmail = inquiryEmail.from;
      final toEmail = inquiryEmail.to;
      final replyToEmail = inquiryEmail.replyTo;
      
      debugPrint('📧 Email headers - From: $senderEmail, To: $toEmail, Reply-To: $replyToEmail');
      
      // For incoming inquiry emails:
      // - "From" should be the customer who sent the inquiry (this is what we want)
      // - "To" should be our account email (kumarionix07@gmail.com)
      // - "Reply-To" might be set to a different email
      
      final accountEmail = AppConstants.emailAddress.toLowerCase();
      
      // Extract customer email from Gmail message with proper priority
      // Priority: 1. customerEmail from PDF, 2. From (sender) if not account email, 
      //           3. Reply-To if not account email, 4. To field if it's not account email
      String? customerEmailFromGmail;
      
      // First, try to use "From" email (the sender is the customer)
      if (senderEmail.isNotEmpty && senderEmail.toLowerCase() != accountEmail) {
        customerEmailFromGmail = senderEmail;
        debugPrint('✅ Using From email as customer email: $customerEmailFromGmail');
      } 
      // If "From" is account email (parsing error), try Reply-To
      else if (replyToEmail != null && replyToEmail.isNotEmpty && 
               replyToEmail.toLowerCase() != accountEmail) {
        customerEmailFromGmail = replyToEmail;
        debugPrint('✅ Using Reply-To email as customer email: $customerEmailFromGmail');
      }
      // If "From" is account email and "To" is not account email, use "To" 
      // (this handles cases where email parsing might be reversed)
      else if (toEmail != null && toEmail.isNotEmpty && 
               toEmail.toLowerCase() != accountEmail) {
        customerEmailFromGmail = toEmail;
        debugPrint('✅ Using To email as customer email (From was account email): $customerEmailFromGmail');
      }
      // Last resort: if senderEmail is account email, it might be a parsing issue
      // Check if we can extract from the raw email data
      else if (senderEmail.toLowerCase() == accountEmail) {
        debugPrint('⚠️ WARNING: Sender email matches account email. Email parsing may be incorrect.');
        debugPrint('⚠️ Attempting to find customer email from alternative sources...');
        
        // If "To" field exists and is different from account email, use it
        // (This handles cases where email parsing might be reversed or incorrect)
        if (toEmail != null && toEmail.isNotEmpty && toEmail.toLowerCase() != accountEmail) {
          customerEmailFromGmail = toEmail;
          debugPrint('✅ Using To email as customer email (From was account email): $customerEmailFromGmail');
        } else {
          // If we still don't have an email, log all available information for debugging
          debugPrint('❌ Could not determine customer email from Gmail headers.');
          debugPrint('❌ Available data - From: $senderEmail, To: $toEmail, Reply-To: $replyToEmail');
          debugPrint('❌ Account email: $accountEmail');
          customerEmailFromGmail = null;
        }
      } else {
        debugPrint('❌ Could not determine customer email from Gmail headers.');
        debugPrint('❌ Available data - From: $senderEmail, To: $toEmail, Reply-To: $replyToEmail');
        customerEmailFromGmail = null;
      }
      
      // Final validation: Ensure we have a valid customer email
      if (customerEmailFromGmail != null && customerEmailFromGmail.toLowerCase() == accountEmail) {
        debugPrint('⚠️ WARNING: Extracted customer email matches account email. This is likely incorrect.');
        debugPrint('⚠️ Setting customerEmailFromGmail to null to force fallback.');
        customerEmailFromGmail = null;
      }

      // Save PDF file using the fetched data
      final platformFile = PlatformFile(
        name: pdfAttachment.name,
        bytes: pdfData,
        size: pdfData.length,
        path: null,
      );
      final savedPath = await _pdfService.savePDFFile(platformFile);
      
      // Ensure we have a customer email - it should NEVER be null
      // Final priority: 1. customerEmail from PDF, 2. customerEmail from Gmail, 3. senderEmail (if different from account)
      String? finalCustomerEmail = inquiry.customerEmail;
      
      if (finalCustomerEmail == null || finalCustomerEmail.isEmpty) {
        if (customerEmailFromGmail != null && customerEmailFromGmail.isNotEmpty) {
          finalCustomerEmail = customerEmailFromGmail;
          debugPrint('✅ Using customerEmail from Gmail: $finalCustomerEmail');
        } else if (senderEmail.isNotEmpty && senderEmail.toLowerCase() != accountEmail) {
          // Last resort: use senderEmail if it's not the account email
          finalCustomerEmail = senderEmail;
          debugPrint('✅ Using senderEmail as customerEmail (fallback): $finalCustomerEmail');
        } else {
          // This should not happen, but if it does, log a warning
          debugPrint('❌ ERROR: Could not determine customer email. This should not happen!');
          debugPrint('❌ senderEmail: $senderEmail, toEmail: $toEmail, replyToEmail: $replyToEmail');
        }
      } else {
        debugPrint('✅ Using customerEmail from PDF: $finalCustomerEmail');
      }
      
      // Update inquiry with sender email and PDF path
      // senderEmail is the email address of the person who sent the inquiry email
      // customerEmail is the email address to send the quotation to (should always be set)
      final finalInquiry = inquiry.copyWith(
        pdfPath: savedPath,
        senderEmail: senderEmail,
        customerEmail: finalCustomerEmail, // This should never be null now
      );
      
      debugPrint('📧 Final inquiry - senderEmail: $senderEmail, customerEmail: $finalCustomerEmail');
      
      // Validate that customerEmail is set
      if (finalCustomerEmail == null || finalCustomerEmail.isEmpty) {
        debugPrint('❌ CRITICAL ERROR: customerEmail is still null after all attempts!');
      }

      final savedInquiry = await ref.read(inquiryProvider.notifier).addInquiry(finalInquiry);

      setState(() => _isFetchingInquiry = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inquiry fetched from email and processed successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && savedInquiry?.id != null) {
            context.push('/inquiry-detail/${savedInquiry!.id}');
          }
        });
      }
    } catch (e) {
      setState(() => _isFetchingInquiry = false);
      if (mounted) {
        String errorMsg = e.toString().replaceAll('Exception: ', '');
        
        // Handle MissingPluginException for web
        if (errorMsg.contains('MissingPluginException') || 
            errorMsg.contains('No implementation found') ||
            errorMsg.contains('OAuth2')) {
          // Show a dialog to guide user through sign-in
          if (mounted) {
            // Close any existing dialogs first
            Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
            
            showDialog(
              context: context,
              barrierDismissible: true,
              builder: (dialogContext) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Gmail Access Setup'),
                  ],
                ),
                content: const Text(
                  'To automatically access your Gmail (kumarionix07@gmail.com), '
                  'you need to sign in with your Google account.\n\n'
                  'This is a one-time setup. After signing in, the app will automatically fetch Customer Inquiry PDFs.\n\n'
                  'Click "Sign In" below to start.'
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      // Close dialog first
                      Navigator.of(dialogContext).pop();
                      
                      // Show loading indicator
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Opening Gmail sign-in...'),
                            backgroundColor: Colors.blue,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      
                      // Small delay to ensure dialog is closed
                      await Future.delayed(const Duration(milliseconds: 300));
                      
                      // Retry with sign-in prompt
                      try {
                        await _getInquiryFromMail();
                      } catch (e) {
                        debugPrint('Error after OAuth2 dialog: $e');
                      }
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Sign In with Gmail'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          }
        } else if (errorMsg.contains('sign in') || 
                   errorMsg.contains('authentication') || 
                   errorMsg.contains('cancelled') ||
                   errorMsg.contains('Please sign in')) {
          // Close any existing dialogs first
          if (mounted) {
            Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
          }
          // Show sign-in dialog with better messaging
          _showGmailSignInDialog('inquiry');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 8),
              action: errorMsg.contains('sign in') || errorMsg.contains('Gmail')
                ? SnackBarAction(
                    label: 'Sign In',
                    textColor: Colors.white,
                    onPressed: () {
                      _showGmailSignInDialog('inquiry');
                    },
                  )
                : null,
            ),
          );
        }
      }
    }
  }

  Future<EmailMessage?> _showEmailSelectionDialog(List<EmailMessage> emails, String type) async {
    return showDialog<EmailMessage>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select ${type == 'inquiry' ? 'Inquiry' : 'PO'} Email'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: emails.length,
            itemBuilder: (context, index) {
              final email = emails[index];
              return ListTile(
                leading: const Icon(Icons.email),
                title: Text(
                  email.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'From: ${email.from}\n${email.attachments.length} attachment(s)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, email),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showGmailSignInDialog(String type) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.email, color: Colors.blue),
            SizedBox(width: 8),
            Text('Gmail Sign-In Required'),
          ],
        ),
        content: const Text(
          'To automatically access your Gmail (kumarionix07@gmail.com) and fetch Customer Inquiry PDFs, '
          'you need to sign in with your Google account.\n\n'
          'This is a one-time setup. After signing in, the app will automatically access your emails.\n\n'
          'Click "Sign In" below to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              setState(() => _isFetchingInquiry = false);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              // Close dialog first
              Navigator.of(dialogContext).pop();
              
              // Show loading indicator
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Opening Gmail sign-in window...'),
                    backgroundColor: Colors.blue,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
              
              // Small delay to ensure dialog is closed
              await Future.delayed(const Duration(milliseconds: 500));
              
              // Directly trigger Gmail API initialization with interactive sign-in
              try {
                setState(() => _isFetchingInquiry = true);
                
                // Force interactive sign-in by calling initialization directly
                await _emailService.fetchInquiryEmails(maxResults: 10);
                
                // If successful, the method will continue and process emails
                // If it fails, error will be caught below
              } catch (e) {
                setState(() => _isFetchingInquiry = false);
                final errorStr = e.toString();
                debugPrint('Error during sign-in: $e');
                
                // Don't show dialog again if it's a cancellation or OAuth2 setup issue
                if (errorStr.contains('cancelled') || 
                    errorStr.contains('OAuth2') ||
                    errorStr.contains('MissingPluginException')) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(errorStr.contains('OAuth2') || errorStr.contains('MissingPluginException')
                          ? 'Gmail access on web requires OAuth2 setup. Please use manual upload.'
                          : 'Sign-in was cancelled. Please try again.'),
                        backgroundColor: Colors.orange,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                } else {
                  // For other errors, let the normal error handling take over
                  if (type == 'inquiry') {
                    await _getInquiryFromMail();
                  } else {
                    await _getPOFromMail();
                  }
                }
              }
            },
            icon: const Icon(Icons.login),
            label: const Text('Sign In with Gmail'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _getPOFromMail() async {
    try {
      setState(() => _isFetchingPO = true);

      // Fetch emails directly via Gmail API
      final emails = await _emailService.fetchPOEmails(maxResults: 10);

      if (emails.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No PO emails found in inbox'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() => _isFetchingPO = false);
        return;
      }

      // Show email selection dialog if multiple emails
      EmailMessage? selectedEmail;
      if (emails.length > 1) {
        selectedEmail = await _showEmailSelectionDialog(emails, 'PO');
        if (selectedEmail == null) {
          setState(() => _isFetchingPO = false);
          return;
        }
      } else {
        selectedEmail = emails.first;
      }

      // Process the selected PO email with PDF attachment
      final poEmail = selectedEmail!;
      final pdfAttachment = poEmail.attachments.firstWhere(
        (att) => att.name.toLowerCase().endsWith('.pdf'),
        orElse: () => throw Exception('No PO PDF attachment found in email'),
      );

      // Fetch attachment data if not already loaded
      Uint8List pdfData;
      if (pdfAttachment.data.isEmpty && pdfAttachment.attachmentId != null && pdfAttachment.messageId != null) {
        // Need to fetch attachment data from Gmail API
        pdfData = await _emailService.fetchAttachmentData(pdfAttachment.messageId!, pdfAttachment.attachmentId!);
      } else {
        pdfData = pdfAttachment.data;
      }

      // Extract PO data from PDF
      final po = await _pdfService.extractPODataFromPDFBytes(pdfData, pdfAttachment.name);

      // Save PDF file
      final platformFile = PlatformFile(
        name: pdfAttachment.name,
        bytes: pdfAttachment.data,
        size: pdfAttachment.data.length,
        path: null,
      );
      final savedPath = await _pdfService.savePDFFile(platformFile);
      final finalPO = po.copyWith(pdfPath: savedPath);

      // Save to database
      final savedPO = await ref.read(poProvider.notifier).addPurchaseOrder(finalPO);

      setState(() => _isFetchingPO = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PO fetched from email and processed successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && savedPO?.id != null) {
            context.push('/po-detail/${savedPO!.id}');
          }
        });
      }
    } catch (e) {
      setState(() => _isFetchingPO = false);
      if (mounted) {
        String errorMsg = e.toString().replaceAll('Exception: ', '');
        
        // Handle MissingPluginException for web
        if (errorMsg.contains('MissingPluginException') || 
            errorMsg.contains('No implementation found')) {
          errorMsg = 'Gmail email fetching on web requires OAuth2 setup.\n\n'
              'Please use manual upload:\n'
              '1. Download PDFs from your Gmail inbox\n'
              '2. Use "Upload PO" button';
        }
        
        if (errorMsg.contains('sign in') || errorMsg.contains('authentication')) {
          // Show sign-in dialog
          _showGmailSignInDialog('PO');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 8),
            ),
          );
        }
      }
    }
  }

  Future<bool> _showEmailFetchInfoDialog(String title, String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blue),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context, true);
                context.push('/upload-inquiry');
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Go to Upload Inquiry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context, true);
                context.push('/upload');
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Go to Upload PO'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
        ],
      ),
    ) ?? false;
  }

  /// Show dialog to select an inquiry for quotation generation
  Future<void> _showGenerateQuotationDialog() async {
    // Load inquiries first
    await ref.read(inquiryProvider.notifier).loadInquiries();
    final inquiryState = ref.read(inquiryProvider);
    
    if (inquiryState.inquiries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No inquiries available. Please create an inquiry first.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Filter inquiries that don't have a quotation yet (status is 'pending' or 'reviewed')
    final availableInquiries = inquiryState.inquiries
        .where((inquiry) => 
            inquiry.quotationId == null && 
            (inquiry.status == 'pending' || inquiry.status == 'reviewed'))
        .toList();

    if (availableInquiries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No inquiries available for quotation generation. All inquiries already have quotations.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    // Show inquiry selection dialog
    final selectedInquiry = await showDialog<CustomerInquiry>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Inquiry for Quotation'),
        content: SizedBox(
          width: double.maxFinite,
          child: inquiryState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : availableInquiries.isEmpty
                  ? const Text('No inquiries available')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: availableInquiries.length,
                      itemBuilder: (context, index) {
                        final inquiry = availableInquiries[index];
                        return ListTile(
                          leading: const Icon(Icons.question_answer, color: Colors.orange),
                          title: Text(
                            inquiry.inquiryNumber,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Customer: ${inquiry.customerName}'),
                              Text('Items: ${inquiry.items.length}'),
                              Text('Status: ${inquiry.status}'),
                            ],
                          ),
                          onTap: () => Navigator.of(context).pop(inquiry),
                        );
                      },
                    ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    // Navigate to create quotation screen if inquiry was selected
    if (selectedInquiry != null && selectedInquiry.id != null) {
      if (mounted) {
        context.push('/create-quotation/${selectedInquiry.id}');
      }
    }
  }

  void _showEmailConfigDialog(String type) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.settings, color: Colors.blue),
            SizedBox(width: 8),
            Text('Email Configuration Required'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To fetch $type emails, you need to configure your Gmail app password in Settings.',
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                context.push('/settings');
              },
              icon: const Icon(Icons.settings),
              label: const Text('Go to Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
