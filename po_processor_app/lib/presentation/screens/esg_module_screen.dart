import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive_helper.dart';

/// Overall ESG (Environmental, Social, Governance) module for Planning & Forecasting.
/// Populated with mock data for demonstration.
class EsgModuleScreen extends ConsumerStatefulWidget {
  final bool embedInDashboard;

  const EsgModuleScreen({super.key, this.embedInDashboard = false});

  @override
  ConsumerState<EsgModuleScreen> createState() => _EsgModuleScreenState();
}

class _EsgModuleScreenState extends ConsumerState<EsgModuleScreen> {
  // Mock ESG data for demonstration (aligned with existing demo data style)
  static const _mockData = _EsgMockData();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dashboardBackground,
      appBar: AppBar(
        elevation: 0,
        leading: widget.embedInDashboard ? null : IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
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
          'Overall ESG Module',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: ResponsiveHelper.responsivePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            Text(
              'Environmental, Social & Governance metrics for Planning & Forecasting.',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),

            // Environmental
            _buildSectionTitle(context, 'Environmental', Icons.eco),
            const SizedBox(height: 12),
            _buildMetricCard(
              'Carbon Footprint',
              '${_mockData.carbonFootprintKgCo2.toStringAsFixed(2)} kg CO₂',
              'Per unit (12-month avg)',
              Icons.cloud_outlined,
              AppTheme.iconGraphGreen,
            ),
            const SizedBox(height: 10),
            _buildMetricCard(
              'Waste Reduction Score',
              '${_mockData.wasteReductionScore.toStringAsFixed(0)}/100',
              'Recycling & circular economy',
              Icons.recycling,
              AppTheme.secondaryGreen,
            ),
            const SizedBox(height: 10),
            _buildMetricCard(
              'Energy Efficiency',
              '${_mockData.energyEfficiencyPercent.toStringAsFixed(0)}%',
              'Vs. baseline year',
              Icons.bolt,
              AppTheme.warningOrange,
            ),
            const SizedBox(height: 24),

            // Social
            _buildSectionTitle(context, 'Social', Icons.people_outline),
            const SizedBox(height: 12),
            _buildMetricCard(
              'Labor Practices Score',
              '${_mockData.laborPracticesScore.toStringAsFixed(0)}/100',
              'Safety & fair wages',
              Icons.verified_user_outlined,
              AppTheme.infoBlue,
            ),
            const SizedBox(height: 10),
            _buildMetricCard(
              'Community Impact',
              _mockData.communityImpactLabel,
              'Local engagement index',
              Icons.location_city,
              AppTheme.accentGreen,
            ),
            const SizedBox(height: 24),

            // Governance
            _buildSectionTitle(context, 'Governance', Icons.gavel),
            const SizedBox(height: 12),
            _buildMetricCard(
              'Compliance Score',
              '${_mockData.complianceScore.toStringAsFixed(0)}/100',
              'Regulatory & policy',
              Icons.policy,
              AppTheme.primaryGreenDark,
            ),
            const SizedBox(height: 10),
            _buildMetricCard(
              'Ethics & Transparency',
              '${_mockData.ethicsScore.toStringAsFixed(0)}/100',
              'Board & disclosure',
              Icons.balance,
              AppTheme.iconGraphGreen,
            ),
            const SizedBox(height: 24),

            // Overall ESG Score
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.iconGraphGreen.withOpacity(0.15),
                      AppTheme.primaryGreenLight.withOpacity(0.08),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.iconGraphGreen.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.insights,
                        size: 40,
                        color: AppTheme.iconGraphGreen,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Overall ESG Score',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.dashboardText,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_mockData.overallEsgScore.toStringAsFixed(0)}/100 — ${_mockData.overallEsgLabel}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.iconGraphGreen,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Based on Environmental, Social & Governance metrics (demo data).',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 22, color: AppTheme.iconGraphGreen),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppTheme.dashboardText,
              ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.dashboardText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
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
}

/// Mock ESG data for demonstration (aligned with existing demo data).
class _EsgMockData {
  const _EsgMockData();

  // Environmental
  double get carbonFootprintKgCo2 => 2.85;
  double get wasteReductionScore => 68;
  double get energyEfficiencyPercent => 72;

  // Social
  double get laborPracticesScore => 78;
  String get communityImpactLabel => 'Good';

  // Governance
  double get complianceScore => 82;
  double get ethicsScore => 75;

  // Overall (aligned with sustainability score style from seasonal trends)
  double get overallEsgScore => 72;
  String get overallEsgLabel => 'Moderate';
}
