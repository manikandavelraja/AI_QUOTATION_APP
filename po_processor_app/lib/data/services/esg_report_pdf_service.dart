import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

/// Data for ESG report (aligned with [EsgModuleScreen] mock data).
class EsgReportData {
  const EsgReportData({
    this.carbonFootprintKgCo2 = 2.85,
    this.wasteReductionScore = 68,
    this.energyEfficiencyPercent = 72,
    this.scope1CompanyVehicles = 12.5,
    this.scope1OnSiteFuel = 8.2,
    this.scope1ProcessEmissions = 3.1,
    this.laborPracticesScore = 78,
    this.communityImpactLabel = 'Good',
    this.complianceScore = 82,
    this.ethicsScore = 75,
    this.overallEsgScore = 72,
    this.overallEsgLabel = 'Moderate',
  });

  final double carbonFootprintKgCo2;
  final double wasteReductionScore;
  final double energyEfficiencyPercent;
  final double scope1CompanyVehicles;
  final double scope1OnSiteFuel;
  final double scope1ProcessEmissions;
  double get scope1Total => scope1CompanyVehicles + scope1OnSiteFuel + scope1ProcessEmissions;
  final double laborPracticesScore;
  final String communityImpactLabel;
  final double complianceScore;
  final double ethicsScore;
  final double overallEsgScore;
  final String overallEsgLabel;
}

/// Generates ESG (Environmental, Social, Governance) report as PDF.
class EsgReportPdfService {
  /// Returns PDF bytes for the ESG report.
  static Future<Uint8List> generateReport(EsgReportData data) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final dateStr = DateFormat('dd MMM yyyy').format(now);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _title('ESG Report'),
            pw.SizedBox(height: 4),
            pw.Text(
              'Environmental, Social & Governance metrics for Planning & Forecasting',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Generated on $dateStr', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 20),
            _sectionTitle('Environmental'),
            pw.SizedBox(height: 8),
            _metricRow('Carbon Footprint', '${data.carbonFootprintKgCo2.toStringAsFixed(2)} kg CO₂', 'Per unit (12-month avg)'),
            _metricRow('Waste Reduction Score', '${data.wasteReductionScore.toStringAsFixed(0)}/100', 'Recycling & circular economy'),
            _metricRow('Energy Efficiency', '${data.energyEfficiencyPercent.toStringAsFixed(0)}%', 'Vs. baseline year'),
            pw.SizedBox(height: 12),
            _sectionTitle('Emissions scopes (GHG Protocol)'),
            pw.SizedBox(height: 6),
            pw.Text('Scope 1 — Direct emissions', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text('Emissions from sources owned or controlled by the organisation. We measure and report these transparently.', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
            pw.SizedBox(height: 6),
            _scope1Table(data),
            pw.SizedBox(height: 8),
            _scopeParagraph('Scope 2 — Indirect emissions (purchased energy)', 'Emissions from the generation of purchased electricity, steam, heating, and cooling consumed by the organisation. We track our energy footprint and commit to clear disclosure in line with market-based and location-based methodologies.'),
            _scopeParagraph('Scope 3 — Value chain emissions', 'All other indirect emissions occurring in the value chain—upstream (purchased goods, business travel, waste) and downstream (use of sold products, end-of-life treatment). We are committed to transparency across the full lifecycle and to reducing our value chain footprint.'),
            pw.SizedBox(height: 6),
            pw.Text(
              'Our reporting follows internationally recognised frameworks. We are committed to authoritative, accessible disclosure and to continuous improvement of our environmental performance.',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey, fontStyle: pw.FontStyle.italic),
            ),
            pw.SizedBox(height: 14),
            _sectionTitle('Social'),
            pw.SizedBox(height: 8),
            _metricRow('Labor Practices Score', '${data.laborPracticesScore.toStringAsFixed(0)}/100', 'Safety & fair wages'),
            _metricRow('Community Impact', data.communityImpactLabel, 'Local engagement index'),
            pw.SizedBox(height: 14),
            _sectionTitle('Governance'),
            pw.SizedBox(height: 8),
            _metricRow('Compliance Score', '${data.complianceScore.toStringAsFixed(0)}/100', 'Regulatory & policy'),
            _metricRow('Ethics & Transparency', '${data.ethicsScore.toStringAsFixed(0)}/100', 'Board & disclosure'),
            pw.SizedBox(height: 18),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.green800, width: 1),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                children: [
                  pw.Text(
                    'Overall ESG Score',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    '${data.overallEsgScore.toStringAsFixed(0)}/100 — ${data.overallEsgLabel}',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green800),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Based on Environmental, Social & Governance metrics.',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _title(String text) {
    return pw.Text(
      text,
      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
    );
  }

  static pw.Widget _sectionTitle(String text) {
    return pw.Text(
      text,
      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green800),
    );
  }

  static pw.Widget _scope1Table(EsgReportData data) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey, width: 0.5),
      columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1)},
      children: [
        _scope1TableRow('Company vehicles', data.scope1CompanyVehicles),
        _scope1TableRow('On-site fuel combustion', data.scope1OnSiteFuel),
        _scope1TableRow('Process emissions', data.scope1ProcessEmissions),
        pw.TableRow(
          children: [
            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Total Scope 1', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${data.scope1Total.toStringAsFixed(1)} tCO₂e', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
          ],
        ),
      ],
    );
  }

  static pw.TableRow _scope1TableRow(String label, double tCo2e) {
    return pw.TableRow(
      children: [
        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(label, style: const pw.TextStyle(fontSize: 9))),
        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${tCo2e.toStringAsFixed(1)} tCO₂e', style: const pw.TextStyle(fontSize: 9))),
      ],
    );
  }

  static pw.Widget _scopeParagraph(String title, String body) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(body, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
        ],
      ),
    );
  }

  static pw.Widget _metricRow(String title, String value, String subtitle) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 2,
            child: pw.Text(title, style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.Expanded(
            flex: 1,
            child: pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(subtitle, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
          ),
        ],
      ),
    );
  }
}
