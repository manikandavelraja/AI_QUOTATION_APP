import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive_helper.dart';
import '../../data/services/esg_report_pdf_service.dart';

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
  bool _isDownloading = false;

  Future<void> _downloadReport() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      const data = EsgReportData(
        carbonFootprintKgCo2: 2.85,
        wasteReductionScore: 68,
        energyEfficiencyPercent: 72,
        scope1CompanyVehicles: 12.5,
        scope1OnSiteFuel: 8.2,
        scope1ProcessEmissions: 3.1,
        laborPracticesScore: 78,
        communityImpactLabel: 'Good',
        complianceScore: 82,
        ethicsScore: 75,
        overallEsgScore: 72,
        overallEsgLabel: 'Moderate',
      );
      final bytes = await EsgReportPdfService.generateReport(data);
      await Printing.sharePdf(bytes: bytes, filename: 'ESG_Report.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ESG report downloaded')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download report: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

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
        actions: [
          IconButton(
            icon: _isDownloading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download, color: Colors.white),
            onPressed: _isDownloading ? null : _downloadReport,
            tooltip: 'Download report',
          ),
        ],
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
            const SizedBox(height: 16),
            // Download report button (below subtitle)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isDownloading ? null : _downloadReport,
                icon: _isDownloading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(_isDownloading ? 'Generating…' : 'Download report'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.iconGraphGreen,
                  side: const BorderSide(color: AppTheme.iconGraphGreen),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
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
            const SizedBox(height: 20),
            // Emissions scopes (GHG Protocol) — sustainability communications
            _buildSectionTitle(context, 'Emissions scopes (GHG Protocol)', Icons.science_outlined),
            const SizedBox(height: 10),
            _buildScope1CardWithValues(context),
            const SizedBox(height: 10),
            _buildScopeCard(
              context,
              'Scope 2 — Indirect emissions (purchased energy)',
              'Emissions from the generation of purchased electricity, steam, heating, and cooling consumed by the organisation. We track our energy footprint and commit to clear disclosure in line with market-based and location-based methodologies.',
              Icons.bolt_outlined,
            ),
            const SizedBox(height: 10),
            _buildScopeCard(
              context,
              'Scope 3 — Value chain emissions',
              'All other indirect emissions occurring in the value chain—upstream (purchased goods, business travel, waste) and downstream (use of sold products, end-of-life treatment). We are committed to transparency across the full lifecycle and to reducing our value chain footprint.',
              Icons.account_tree_outlined,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Our reporting follows internationally recognised frameworks. We are committed to authoritative, accessible disclosure and to continuous improvement of our environmental performance.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.textSecondary,
                ),
              ),
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

  Widget _buildScope1CardWithValues(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.iconGraphGreen.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.directions_car_outlined, color: AppTheme.iconGraphGreen, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Scope 1 — Direct emissions',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.dashboardText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Emissions from sources owned or controlled by the organisation. We measure and report these transparently as the foundation of our environmental accountability.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.dashboardBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.iconGraphGreen.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        _scope1Row('Company vehicles', _mockData.scope1CompanyVehicles),
                        const SizedBox(height: 6),
                        _scope1Row('On-site fuel combustion', _mockData.scope1OnSiteFuel),
                        const SizedBox(height: 6),
                        _scope1Row('Process emissions', _mockData.scope1ProcessEmissions),
                        const Divider(height: 16),
                        _scope1Row('Total Scope 1', _mockData.scope1Total, isTotal: true),
                      ],
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

  Widget _scope1Row(String label, double tCo2e, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 13 : 12,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
            color: AppTheme.dashboardText,
          ),
        ),
        Text(
          '${tCo2e.toStringAsFixed(1)} tCO₂e',
          style: TextStyle(
            fontSize: isTotal ? 14 : 12,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
            color: AppTheme.iconGraphGreen,
          ),
        ),
      ],
    );
  }

  Widget _buildScopeCard(
    BuildContext context,
    String title,
    String body,
    IconData icon,
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.iconGraphGreen.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppTheme.iconGraphGreen, size: 24),
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
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
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

  // Scope 1 — Direct emissions (static inputs, tCO2e)
  double get scope1CompanyVehicles => 12.5;
  double get scope1OnSiteFuel => 8.2;
  double get scope1ProcessEmissions => 3.1;
  double get scope1Total => scope1CompanyVehicles + scope1OnSiteFuel + scope1ProcessEmissions;

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
