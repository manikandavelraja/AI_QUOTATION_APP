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
import '../providers/quotation_provider.dart';
import '../../data/services/catalog_service.dart';
import '../../domain/entities/quotation.dart';
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
  final _catalogService = CatalogService();
  bool _isFetchingInquiry = false;
  bool _isFetchingPO = false;
  int _processedCount = 0;
  int _successCount = 0;
  int _errorCount = 0;

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
                      // QuickActions moved to top
                      _buildQuickActions(context),
                      const SizedBox(height: 24),
                      _buildStatsGrid(context, stats),
                      const SizedBox(height: 24),
                      _buildMonthlyUsageGraph(context, monthlyData),
                      const SizedBox(height: 24),
                      _buildExpiringAlerts(context, poState),
                      const SizedBox(height: 24),
                      _buildDraftQuotationsList(context),
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
    final statItems = [
      {
        'title': 'today_purchase_orders'.tr(),
        'value': '${stats['todayPOs'] ?? 0}',
        'icon': Icons.description,
        'gradient': [Colors.blue.shade400, Colors.blue.shade600],
        'iconBg': Colors.blue.shade50,
      },
      {
        'title': 'total_po_value'.tr(),
        'value': '₹${(stats['totalValue'] ?? 0).toStringAsFixed(0)}',
        'icon': Icons.attach_money,
        'gradient': [Colors.green.shade400, Colors.green.shade600],
        'iconBg': Colors.green.shade50,
      },
      {
        'title': 'expiring_this_week'.tr(),
        'value': '${stats['expiringThisWeek'] ?? 0}',
        'icon': Icons.warning,
        'gradient': [Colors.orange.shade400, Colors.orange.shade600],
        'iconBg': Colors.orange.shade50,
      },
      {
        'title': 'total_pos'.tr(),
        'value': '${stats['totalPOs'] ?? 0}',
        'icon': Icons.inventory,
        'gradient': [Colors.purple.shade400, Colors.purple.shade600],
        'iconBg': Colors.purple.shade50,
      },
    ];

    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: statItems.length,
        itemBuilder: (context, index) {
          final item = statItems[index];
          return Container(
            width: 180,
            margin: const EdgeInsets.only(right: 16),
            child: _buildStatCard(
              context,
              item['title'] as String,
              item['value'] as String,
              item['icon'] as IconData,
              item['gradient'] as List<Color>,
              item['iconBg'] as Color,
            ),
          );
        },
      ),
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
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, animValue, child) {
        return Transform.scale(
          scale: 0.8 + (animValue * 0.2),
          child: Opacity(
            opacity: animValue,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    gradientColors[0],
                    gradientColors[1],
                    gradientColors[1].withOpacity(0.9),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: gradientColors[0].withOpacity(0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Decorative circles
                  Positioned(
                    top: -20,
                    right: -20,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -30,
                    left: -30,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                  ),
                  // Content
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(icon, size: 36, color: Colors.white),
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              value,
                              style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -1,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.95),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

  /// Build draft quotations list
  Widget _buildDraftQuotationsList(BuildContext context) {
    final quotationState = ref.watch(quotationProvider);
    final draftQuotations = quotationState.quotations
        .where((q) => q.status == 'draft')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // Most recent first

    if (draftQuotations.isEmpty) {
      return const SizedBox.shrink();
    }

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
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryGreen,
                      AppTheme.primaryGreenLight,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.description, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Draft Quotations',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Text(
                '${draftQuotations.length}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppTheme.primaryGreen,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200, // Fixed height for scrollable list
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: draftQuotations.length,
              itemBuilder: (context, index) {
                final quotation = draftQuotations[index];
                return Container(
                  width: 320,
                  margin: EdgeInsets.only(right: index == draftQuotations.length - 1 ? 0 : 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.blue.shade50,
                        Colors.blue.shade100.withOpacity(0.5),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.2),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.1),
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
                          Expanded(
                            child: Text(
                              quotation.quotationNumber,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
                                  ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Draft',
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.person, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              quotation.customerName,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.shopping_cart, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Text(
                            '${quotation.items.length} item(s)',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '${quotation.currency ?? 'AED'} ${quotation.totalAmount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.blue.shade900,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              context.push('/quotation-detail/${quotation.id}');
                            },
                            icon: const Icon(Icons.arrow_forward, size: 16),
                            label: const Text('View'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Rich loader dialog for email fetching with progress
  void _showRichLoaderDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Update message periodically if processing
            if (_isFetchingInquiry && _processedCount > 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _isFetchingInquiry) {
                  setDialogState(() {});
                }
              });
            }
            
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      Colors.grey.shade50,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated loader
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            strokeWidth: 6,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.primaryGreen,
                            ),
                            backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
                          ),
                        ),
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppTheme.primaryGreen,
                                AppTheme.primaryGreenLight,
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryGreen.withOpacity(0.3),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.email,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                      textAlign: TextAlign.center,
                    ),
                    if (_processedCount > 0) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Processed: $_processedCount | Success: $_successCount | Errors: $_errorCount',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Please wait while we process inquiries...',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    // Animated dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (index) {
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: Duration(milliseconds: 600 + (index * 200)),
                          curve: Curves.easeInOut,
                          builder: (context, value, child) {
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryGreen.withOpacity(
                                  0.3 + (value * 0.7),
                                ),
                                shape: BoxShape.circle,
                              ),
                            );
                          },
                          onEnd: () {
                            // Restart animation if still loading
                            if (mounted && _isFetchingInquiry) {
                              Future.delayed(const Duration(milliseconds: 100), () {
                                if (mounted) setDialogState(() {});
                              });
                            }
                          },
                        );
                      }),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Colors.grey.shade50,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: 2,
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


  /// Extract customer email from Gmail message headers
  String? _extractCustomerEmailFromGmail({
    required String senderEmail,
    String? toEmail,
    String? replyToEmail,
    required String accountEmail,
  }) {
    // First, try to use "From" email (the sender is the customer)
    if (senderEmail.isNotEmpty && senderEmail.toLowerCase() != accountEmail) {
      return senderEmail;
    } 
    // If "From" is account email (parsing error), try Reply-To
    else if (replyToEmail != null && replyToEmail.isNotEmpty && 
             replyToEmail.toLowerCase() != accountEmail) {
      return replyToEmail;
    }
    // If "From" is account email and "To" is not account email, use "To" 
    else if (toEmail != null && toEmail.isNotEmpty && 
             toEmail.toLowerCase() != accountEmail) {
      return toEmail;
    }
    return null;
  }

  /// Process a single email and create draft quotation
  Future<Quotation?> _processSingleEmail(EmailMessage email, int index, int total) async {
    try {
      debugPrint('📧 Processing email ${index + 1}/$total: ${email.subject}');
      
      // Find PDF attachment
      final pdfAttachment = email.attachments.firstWhere(
        (att) => att.name.toLowerCase().endsWith('.pdf') || 
                 att.name.toLowerCase().endsWith('.doc') ||
                 att.name.toLowerCase().endsWith('.docx'),
        orElse: () => throw Exception('No PDF or DOC attachment found in email'),
      );

      // Fetch attachment data if not already loaded
      Uint8List pdfData;
      if (pdfAttachment.data.isEmpty && pdfAttachment.attachmentId != null && pdfAttachment.messageId != null) {
        pdfData = await _emailService.fetchAttachmentData(pdfAttachment.messageId!, pdfAttachment.attachmentId!);
      } else {
        pdfData = pdfAttachment.data;
      }

      if (pdfData.isEmpty) {
        throw Exception('Failed to fetch PDF attachment data from email');
      }

      // Extract inquiry data from PDF
      CustomerInquiry inquiry;
      if (pdfAttachment.name.toLowerCase().endsWith('.pdf')) {
        inquiry = await _aiService.extractInquiryFromPDFBytes(pdfData, pdfAttachment.name);
      } else {
        throw Exception('DOC file processing not yet implemented. Please use PDF files.');
      }

      // Extract customer email from Gmail headers
      final accountEmail = AppConstants.emailAddress.toLowerCase();
      final customerEmailFromGmail = _extractCustomerEmailFromGmail(
        senderEmail: email.from,
        toEmail: email.to,
        replyToEmail: email.replyTo,
        accountEmail: accountEmail,
      );

      // Determine final customer email
      String? finalCustomerEmail = inquiry.customerEmail ?? customerEmailFromGmail;
      if (finalCustomerEmail == null || finalCustomerEmail.isEmpty || 
          finalCustomerEmail.toLowerCase() == accountEmail) {
        finalCustomerEmail = email.from.isNotEmpty && email.from.toLowerCase() != accountEmail 
            ? email.from 
            : null;
      }

      // Save PDF file
      final platformFile = PlatformFile(
        name: pdfAttachment.name,
        bytes: pdfData,
        size: pdfData.length,
        path: null,
      );
      final savedPath = await _pdfService.savePDFFile(platformFile);
      
      // Save inquiry
      final finalInquiry = inquiry.copyWith(
        pdfPath: savedPath,
        senderEmail: email.from,
        customerEmail: finalCustomerEmail,
      );
      final savedInquiry = await ref.read(inquiryProvider.notifier).addInquiry(finalInquiry);

      // Auto-match prices from catalog and create quotation items
      final quotationItems = <QuotationItem>[];
      for (final inquiryItem in inquiry.items) {
        // Auto-match price from catalog
        final unitPrice = _catalogService.matchItemPrice(
          inquiryItem.itemName,
          description: inquiryItem.description,
        );
        
        final lineTotal = unitPrice * inquiryItem.quantity;
        
        quotationItems.add(QuotationItem(
          itemName: inquiryItem.itemName,
          itemCode: inquiryItem.itemCode,
          description: inquiryItem.description,
          quantity: inquiryItem.quantity,
          unit: inquiryItem.unit,
          unitPrice: unitPrice,
          total: lineTotal,
          manufacturerPart: inquiryItem.manufacturerPart,
        ));
      }

      // Calculate totals (only if items exist)
      double grandTotal = 0.0;
      if (quotationItems.isNotEmpty) {
        final subtotal = quotationItems.fold<double>(0, (sum, item) => sum + item.total);
        final vat = subtotal * 0.05; // 5% VAT
        grandTotal = subtotal + vat;
      }

      // Create draft quotation
      final quotation = Quotation(
        quotationNumber: 'QTN-${DateTime.now().millisecondsSinceEpoch}-${index}',
        quotationDate: DateTime.now(),
        validityDate: DateTime.now().add(const Duration(days: 30)),
        customerName: inquiry.customerName,
        customerAddress: inquiry.customerAddress,
        customerEmail: finalCustomerEmail,
        customerPhone: inquiry.customerPhone,
        items: quotationItems,
        totalAmount: grandTotal,
        currency: 'AED',
        status: 'draft', // Draft status
        createdAt: DateTime.now(),
        inquiryId: savedInquiry?.id,
      );

      // Save quotation
      final savedQuotation = await ref.read(quotationProvider.notifier).addQuotation(quotation);
      
      debugPrint('✅ Successfully processed email ${index + 1}/$total and created draft quotation');
      return savedQuotation;
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      
      // Handle 429 rate limit errors - continue to next email
      if (errorStr.contains('429') || errorStr.contains('rate limit')) {
        debugPrint('⚠️ Rate limit error (429) for email ${index + 1}/$total. Continuing to next email...');
        // Wait a bit before continuing
        await Future.delayed(const Duration(seconds: 2));
        return null;
      }
      
      // For other errors, log and continue
      debugPrint('❌ Error processing email ${index + 1}/$total: $e');
      return null;
    }
  }

  Future<void> _getInquiryFromMail() async {
    // Close any existing dialogs first to prevent stacking
    if (mounted) {
      Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    }
    
    setState(() {
      _isFetchingInquiry = true;
      _processedCount = 0;
      _successCount = 0;
      _errorCount = 0;
    });

    // Show rich loading dialog with progress
    if (mounted) {
      _showRichLoaderDialog(context, 'Fetching Inquiries from Gmail...');
    }
    
    try {
      // Fetch up to 10 most recent inquiry emails
      final emails = await _emailService.fetchInquiryEmails(maxResults: 10);

      if (emails.isEmpty) {
        setState(() => _isFetchingInquiry = false);
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No inquiry emails found in inbox'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      debugPrint('📧 Found ${emails.length} inquiry email(s). Processing in bulk...');

      // Process each email in a loop
      final processedQuotations = <Quotation>[];
      
      for (int i = 0; i < emails.length; i++) {
        if (!mounted) break;
        
        final email = emails[i];
        setState(() => _processedCount = i + 1);
        
        // Update loader message
        if (mounted) {
          // Close and reopen loader with updated message
          try {
            Navigator.of(context, rootNavigator: true).pop();
          } catch (_) {}
          _showRichLoaderDialog(
            context, 
            'Processing ${i + 1}/${emails.length}: ${email.subject}',
          );
        }

        try {
          final quotation = await _processSingleEmail(email, i, emails.length);
          if (quotation != null) {
            processedQuotations.add(quotation);
            setState(() => _successCount++);
          } else {
            setState(() => _errorCount++);
          }
        } catch (e) {
          debugPrint('❌ Failed to process email ${i + 1}: $e');
          setState(() => _errorCount++);
          // Continue to next email
          continue;
        }

        // Small delay between emails to avoid rate limiting
        if (i < emails.length - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      setState(() => _isFetchingInquiry = false);
      
      // Dismiss loader dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // Show summary
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Bulk processing complete: $_successCount draft quotation(s) created, $_errorCount failed',
            ),
            backgroundColor: _successCount > 0 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      // Refresh quotations list
      await ref.read(quotationProvider.notifier).loadQuotations();
      
    } catch (e) {
      setState(() => _isFetchingInquiry = false);
      
      // Dismiss loader dialog on error
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {
          // Dialog might already be closed, ignore error
        }
      }
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
