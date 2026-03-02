import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../providers/quotation_provider.dart';
import '../../domain/entities/quotation.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive_helper.dart';

class ViewQuotationScreen extends ConsumerWidget {
  final bool embedInDashboard;

  const ViewQuotationScreen({super.key, this.embedInDashboard = false});

  /// Last 6 months: per month counts using same categories as cards (Total Quotation, Order Received, Order Not Received).
  static Map<String, Map<String, dynamic>> _getQuotationMonthlyStatistics(
    List<Quotation> quotations,
  ) {
    final now = DateTime.now();
    final Map<String, Map<String, dynamic>> monthlyData = {};
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey =
          '${month.year}-${month.month.toString().padLeft(2, '0')}';
      final monthName = DateFormat('MMM').format(month);
      final monthQuotations = quotations.where((q) {
        return q.quotationDate.year == month.year &&
            q.quotationDate.month == month.month;
      }).toList();
      // Use same category logic as Total Quotation / Order Received / Order Not Received cards
      final total = _filterByCategory(monthQuotations, 'total').length;
      final orderReceived =
          _filterByCategory(monthQuotations, 'order_received').length;
      final orderNotReceived =
          _filterByCategory(monthQuotations, 'order_not_received').length;
      monthlyData[monthKey] = {
        'name': monthName,
        'total': total,
        'orderReceived': orderReceived,
        'orderNotReceived': orderNotReceived,
      };
    }
    return monthlyData;
  }

  static List<Quotation> _filterByCategory(List<Quotation> all, String category) {
    switch (category) {
      case 'total':
        return all;
      case 'order_received':
        return all.where((q) => q.status == 'accepted').toList();
      case 'order_not_received':
        return all
            .where((q) =>
                q.status == 'draft' ||
                q.status == 'sent' ||
                q.status == 'rejected' ||
                q.status == 'expired')
            .toList();
      case 'order_partially_received':
        return all.where((q) => q.status == 'partially_received').toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotationState = ref.watch(quotationProvider);
    final allQuotations = quotationState.quotations;
    final isMobile = ResponsiveHelper.isMobile(context);

    // Same categories as graph: Total Quotation, Order Received, Order Not Received (and Order Partially Received)
    final statItems = [
      {
        'title': 'Total Quotation',
        'count': _filterByCategory(allQuotations, 'total').length,
        'icon': Icons.description,
        'gradient': [
          AppTheme.iconGraphGreen,
          AppTheme.iconGraphGreen.withOpacity(0.85),
        ],
      },
      {
        'title': 'Order Received',
        'count': _filterByCategory(allQuotations, 'order_received').length,
        'icon': Icons.check_circle,
        'gradient': [
          AppTheme.totalPoValueIcon,
          AppTheme.totalPoValueIcon.withOpacity(0.85),
        ],
      },
      {
        'title': 'Order Not Received',
        'count': _filterByCategory(allQuotations, 'order_not_received').length,
        'icon': Icons.pending_actions,
        'gradient': [
          AppTheme.expireWeekIconRed,
          AppTheme.expireWeekIconRed.withOpacity(0.85),
        ],
      },
      {
        'title': 'Order Partially Received',
        'count': _filterByCategory(allQuotations, 'order_partially_received').length,
        'icon': Icons.inventory_2,
        'gradient': [
          AppTheme.totalPoIcon,
          AppTheme.totalPoIcon.withOpacity(0.85),
        ],
      },
    ];

    // Compact height to match dashboard PO stat cards
    const double cardsHeight = 160;

    final cardsContent = quotationState.isLoading
        ? const Center(child: CircularProgressIndicator())
        : SizedBox(
            height: cardsHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 2 : 4),
              itemCount: statItems.length,
              itemBuilder: (context, index) {
                final item = statItems[index];
                return Container(
                  width: ResponsiveHelper.responsiveStatCardWidth(context),
                  margin: EdgeInsets.only(right: isMobile ? 12 : 16),
                  child: _QuotationCountCard(
                    title: item['title'] as String,
                    count: item['count'] as int,
                    icon: item['icon'] as IconData,
                    gradientColors: item['gradient'] as List<Color>,
                  ),
                );
              },
            ),
          );

    final monthlyData = _getQuotationMonthlyStatistics(allQuotations);

    if (embedInDashboard) {
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Text(
                    'View Quotation',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () =>
                        ref.read(quotationProvider.notifier).loadQuotations(),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            cardsContent,
            const SizedBox(height: 24),
            _QuotationMonthlyUsageGraph(monthlyData: monthlyData),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('View Quotation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(quotationProvider.notifier).loadQuotations(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cardsContent,
            const SizedBox(height: 24),
            _QuotationMonthlyUsageGraph(
              monthlyData: _getQuotationMonthlyStatistics(allQuotations),
            ),
          ],
        ),
      ),
    );
  }
}

/// Count card matching dashboard KPI style: gradient background, icon, large count, label.
class _QuotationCountCard extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final List<Color> gradientColors;

  const _QuotationCountCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return Container(
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withOpacity(0.45),
            blurRadius: 16,
            offset: const Offset(0, 8),
            spreadRadius: 2,
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
          Positioned(
            top: -12,
            right: -12,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ),
          Positioned(
            bottom: -16,
            left: -16,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(isMobile ? 10 : 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(isMobile ? 6 : 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    size: ResponsiveHelper.responsiveIconSize(context, 24),
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: ResponsiveHelper.responsiveFontSize(context, 28),
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -1,
                            height: 1.0,
                          ),
                          maxLines: 1,
                        ),
                      ),
                      SizedBox(height: isMobile ? 2 : 4),
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: ResponsiveHelper.responsiveFontSize(context, 11),
                            color: Colors.white.withOpacity(0.95),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            height: 1.15,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
}

/// Three-line graph: Total (yellow), Order Received (green), Order Not Received (red) per month.
class _QuotationMonthlyUsageGraph extends StatelessWidget {
  final Map<String, Map<String, dynamic>> monthlyData;

  const _QuotationMonthlyUsageGraph({required this.monthlyData});

  static const Color _lineTotal = Color(0xFFF9A825); // yellow
  static const Color _lineOrderReceived = AppTheme.iconGraphGreen; // green
  static const Color _lineOrderNotReceived = AppTheme.expireWeekIconRed; // red

  @override
  Widget build(BuildContext context) {
    if (monthlyData.isEmpty) return const SizedBox.shrink();

    final spots = monthlyData.entries.toList();
    final maxCount = monthlyData.values.isEmpty
        ? 0
        : monthlyData.values
            .map((e) => e['total'] as int)
            .reduce((a, b) => a > b ? a : b);

    final isMobile = ResponsiveHelper.isMobile(context);
    final maxY = maxCount > 0 ? (maxCount * 1.2).clamp(1.0, double.infinity) : 10.0;

    return Container(
      padding: ResponsiveHelper.responsiveCardPadding(context),
      decoration: BoxDecoration(
        color: AppTheme.monthlyUsageBackground,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.responsiveBorderRadius(context),
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
                padding: EdgeInsets.all(isMobile ? 8 : 10),
                decoration: BoxDecoration(
                  color: AppTheme.iconGraphGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
                ),
                child: Icon(
                  Icons.show_chart,
                  color: AppTheme.iconGraphGreen,
                  size: ResponsiveHelper.responsiveIconSize(context, 24),
                ),
              ),
              SizedBox(width: isMobile ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly Usage Statistics',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: ResponsiveHelper.responsiveFontSize(
                              context,
                              18,
                            ),
                            color: AppTheme.dashboardText,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: isMobile ? 2 : 4),
                    Text(
                      'Total, Order Received & Order Not Received over time',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.dashboardText.withOpacity(0.7),
                            fontSize: ResponsiveHelper.responsiveFontSize(
                              context,
                              12,
                            ),
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 12 : 16),
          SizedBox(
            height: ResponsiveHelper.responsiveChartHeight(context),
            child: LineChart(
              LineChartData(
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppTheme.textSecondary.withOpacity(0.1),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        final v = value.toInt();
                        if (v >= 0 && v <= maxY.ceil()) {
                          return Text(
                            v.toString(),
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.textSecondary,
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
                                color: AppTheme.textSecondary,
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
                  // Total quotations - yellow
                  LineChartBarData(
                    spots: spots.asMap().entries.map((e) {
                      return FlSpot(
                        e.key.toDouble(),
                        (e.value.value['total'] as int).toDouble(),
                      );
                    }).toList(),
                    isCurved: true,
                    color: _lineTotal,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _lineTotal.withOpacity(0.12),
                    ),
                  ),
                  // Order received - green
                  LineChartBarData(
                    spots: spots.asMap().entries.map((e) {
                      return FlSpot(
                        e.key.toDouble(),
                        (e.value.value['orderReceived'] as int).toDouble(),
                      );
                    }).toList(),
                    isCurved: true,
                    color: _lineOrderReceived,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _lineOrderReceived.withOpacity(0.12),
                    ),
                  ),
                  // Order not received - red
                  LineChartBarData(
                    spots: spots.asMap().entries.map((e) {
                      return FlSpot(
                        e.key.toDouble(),
                        (e.value.value['orderNotReceived'] as int).toDouble(),
                      );
                    }).toList(),
                    isCurved: true,
                    color: _lineOrderNotReceived,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _lineOrderNotReceived.withOpacity(0.12),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    tooltipRoundedRadius: 8,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    getTooltipItems: (List<LineBarSpot> touchedSpots) {
                      return touchedSpots.map((LineBarSpot s) {
                        String label;
                        if (s.barIndex == 0) {
                          label = 'Total: ${s.y.toInt()}';
                        } else if (s.barIndex == 1) {
                          label = 'Order Received: ${s.y.toInt()}';
                        } else {
                          label = 'Order Not Received: ${s.y.toInt()}';
                        }
                        return LineTooltipItem(
                          label,
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(_lineTotal),
              const SizedBox(width: 6),
              Text(
                'Total',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: AppTheme.dashboardText,
                    ),
              ),
              const SizedBox(width: 20),
              _legendDot(_lineOrderReceived),
              const SizedBox(width: 6),
              Text(
                'Order Received',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: AppTheme.dashboardText,
                    ),
              ),
              const SizedBox(width: 20),
              _legendDot(_lineOrderNotReceived),
              const SizedBox(width: 6),
              Text(
                'Order Not Received',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: AppTheme.dashboardText,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
    );
  }
}
