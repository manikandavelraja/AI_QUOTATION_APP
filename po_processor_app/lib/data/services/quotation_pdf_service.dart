import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../domain/entities/quotation.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/utils/number_to_words.dart';

/// Service for generating quotation PDF files
class QuotationPDFService {
  Uint8List? _logoBytes;
  
  /// Load logo image from assets
  Future<Uint8List?> _loadLogo() async {
    if (_logoBytes != null) return _logoBytes;
    
    try {
      final ByteData logoData = await rootBundle.load('assets/icons/al-kareem.jpg');
      _logoBytes = logoData.buffer.asUint8List();
      return _logoBytes;
    } catch (e) {
      // If logo fails to load, continue without it
      return null;
    }
  }
  
  /// Get logo bytes for use in PDF
  Uint8List? get logoBytes => _logoBytes;
  /// Generate a partial PDF file from quotation data (only items with prices)
  /// Filters out pending items and adds a disclaimer if items are missing
  /// Returns PDF bytes that can be attached to emails
  Future<Uint8List> generatePartialQuotePDF(Quotation quotation) async {
    try {
      // Load logo
      await _loadLogo();
      
      // Filter out pending items - only include items with status 'ready'
      final readyItems = quotation.items.where((item) => item.status == 'ready').toList();
      final hasPendingItems = quotation.items.any((item) => item.status == 'pending');
      
      // Create a modified quotation with only ready items
      final partialQuotation = quotation.copyWith(
        items: readyItems,
      );
      
      final pdf = pw.Document();
      final currencyCode = partialQuotation.currency ?? 'AED';
      final currencySymbol = CurrencyHelper.getCurrencySymbol(currencyCode);
      
      // Calculate subtotal and VAT from ready items only
      final subtotal = readyItems.fold<double>(
        0.0,
        (sum, item) => sum + item.total,
      );
      final vat = subtotal * 0.05; // 5% VAT
      final grandTotal = subtotal + vat;
      
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return [
              // Header with company name and quotation title
              _buildHeader(partialQuotation, pdf.document),
              pw.SizedBox(height: 15),
              
              // Greeting
              pw.Text(
                'Dear Sir/Mam,',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'We thank you for your inquiry and pleased to offer our best prices as below',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 15),
              
              // Items Table (only ready items)
              _buildItemsTable(partialQuotation, currencySymbol),
              pw.SizedBox(height: 10),
              
              // Amount in words
              _buildAmountInWords(grandTotal, currencyCode),
              pw.SizedBox(height: 20),
              
              // Terms and Conditions
              _buildTermsSection(partialQuotation.terms ?? ''),
              pw.SizedBox(height: 20),
              
              // Disclaimer if items are missing
              if (hasPendingItems) _buildPendingItemsDisclaimer(quotation),
              pw.SizedBox(height: 20),
              
              // Footer
              _buildFooter(pdf.document),
              
              // Red footer bar
              _buildFooterBar(),
            ];
          },
        ),
      );
      
      return pdf.save();
    } catch (e) {
      throw Exception('Failed to generate partial quotation PDF: $e');
    }
  }

  /// Generate a PDF file from quotation data
  /// Returns PDF bytes that can be attached to emails
  Future<Uint8List> generateQuotationPDF(Quotation quotation) async {
    try {
      // Load logo
      await _loadLogo();
      
      final pdf = pw.Document();
      final currencyCode = quotation.currency ?? 'AED';
      final currencySymbol = CurrencyHelper.getCurrencySymbol(currencyCode);
      
      // Calculate subtotal and VAT
      final subtotal = quotation.items.fold<double>(
        0.0,
        (sum, item) => sum + item.total,
      );
      final vat = subtotal * 0.05; // 5% VAT
      final grandTotal = subtotal + vat;
      
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return [
              // Header with company name and quotation title
              _buildHeader(quotation, pdf.document),
              pw.SizedBox(height: 15),
              
              // Greeting
              pw.Text(
                'Dear Sir/Mam,',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'We thank you for your inquiry and pleased to offer our best prices as below',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 15),
              
              // Items Table
              _buildItemsTable(quotation, currencySymbol),
              pw.SizedBox(height: 10),
              
              // Amount in words
              _buildAmountInWords(grandTotal, currencyCode),
              pw.SizedBox(height: 20),
              
              // Terms and Conditions
              _buildTermsSection(quotation.terms ?? ''),
              pw.SizedBox(height: 20),
              
              // Footer
              _buildFooter(pdf.document),
              
              // Red footer bar
              _buildFooterBar(),
            ];
          },
        ),
      );
      
      return pdf.save();
    } catch (e) {
      throw Exception('Failed to generate quotation PDF: $e');
    }
  }
  
  pw.Widget _buildHeader(Quotation quotation, PdfDocument document) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        // Header with Logo on left and Arabic text on right (horizontal layout)
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // Left side - Logo and English company name
            pw.Expanded(
              child: pw.Row(
                children: [
                  if (_logoBytes != null)
                    pw.Image(
                      pw.MemoryImage(_logoBytes!),
                      width: 80,
                      height: 60,
                    ),
                  if (_logoBytes != null) pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(
                          'AL KAREEM ENTERPRISES L.L.C.',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.red700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Right side - Arabic company name
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  'شركة الكريم ذ.م.م.',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                  textAlign: pw.TextAlign.right,
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 15),
        // QUOTATION title - centered, bold, black uppercase
        pw.Text(
          'QUOTATION',
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 20),
        // Client and Date info in two columns
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Client: ${quotation.customerName}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  if (quotation.customerPhone != null && quotation.customerPhone!.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Attn: ${quotation.customerPhone}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                  if (quotation.inquiryId != null && quotation.inquiryId!.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'RFQ#: ${quotation.inquiryId}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Qtn No: ${quotation.quotationNumber}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 20),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Date: ${_formatDate(quotation.quotationDate)}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                if (quotation.customerAddress != null && quotation.customerAddress!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'TRN: ${quotation.customerAddress}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
      ],
    );
  }
  
  
  pw.Widget _buildItemsTable(Quotation quotation, String currencySymbol) {
    final currencyCode = quotation.currency ?? 'AED';
    final subtotal = quotation.items.fold<double>(0.0, (sum, item) => sum + item.total);
    
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.4),  // Sl.
        1: const pw.FlexColumnWidth(1.2), // Purchase Description
        2: const pw.FlexColumnWidth(0.8), // Item of Requisition
        3: const pw.FlexColumnWidth(0.8), // Material Code
        4: const pw.FlexColumnWidth(2.0), // Material Description
        5: const pw.FlexColumnWidth(1.0),  // Manufacturer Parts
        6: const pw.FlexColumnWidth(0.6),  // Qty
        7: const pw.FlexColumnWidth(0.6),  // UOM
        8: const pw.FlexColumnWidth(0.8),  // Unit Price
        9: const pw.FlexColumnWidth(0.8),  // Total AED
        10: const pw.FlexColumnWidth(0.8), // Delivery
      },
      children: [
        // Header row - Blue background with white text
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue700),
          children: [
            _buildTableCell('Sl.', isHeader: true, fontSize: 8, textColor: PdfColors.white),
            _buildTableCell('Purchase Requisition', isHeader: true, fontSize: 8, textColor: PdfColors.white),
            _buildTableCell('Item of Requisition', isHeader: true, fontSize: 8, textColor: PdfColors.white),
            _buildTableCell('Material Code', isHeader: true, fontSize: 8, textColor: PdfColors.white),
            _buildTableCell('Material Description', isHeader: true, fontSize: 8, textColor: PdfColors.white),
            _buildTableCell('Manufacturer Part#', isHeader: true, fontSize: 8, textColor: PdfColors.white),
            _buildTableCell('Qty', isHeader: true, fontSize: 8, textColor: PdfColors.white),
            _buildTableCell('UOM', isHeader: true, fontSize: 8, textColor: PdfColors.white),
            _buildTableCell('Unit Price', isHeader: true, fontSize: 8, textColor: PdfColors.white),
            _buildTableCell('Total $currencyCode', isHeader: true, fontSize: 8, textColor: PdfColors.white),
            _buildTableCell('Delivery', isHeader: true, fontSize: 8, textColor: PdfColors.white),
          ],
        ),
        // Data rows
        ...quotation.items.asMap().entries.map((entry) {
          final index = entry.key + 1;
          final item = entry.value;
          // Use inquiryId as Purchase Requisition if available
          final purchaseRequisition = quotation.inquiryId ?? '';
          // Item of Requisition can be the index or item code
          final itemOfRequisition = item.itemCode ?? '$index';
          return pw.TableRow(
            children: [
              _buildTableCell('$index', fontSize: 8),
              _buildTableCell(purchaseRequisition, fontSize: 8),
              _buildTableCell(itemOfRequisition, fontSize: 8),
              _buildTableCell(item.itemCode ?? '', fontSize: 8),
              _buildTableCell(item.itemName, fontSize: 8),
              _buildTableCell(item.manufacturerPart ?? '', fontSize: 8),
              _buildTableCell(item.quantity.toStringAsFixed(0), fontSize: 8),
              _buildTableCell(item.unit, fontSize: 8),
              _buildTableCell(item.unitPrice.toStringAsFixed(2), fontSize: 8),
              _buildTableCell(item.total.toStringAsFixed(2), fontSize: 8),
              _buildTableCell('Ex-stock', fontSize: 8), // Default delivery
            ],
          );
        }),
        // Empty row
        pw.TableRow(
          children: List.generate(11, (_) => _buildTableCell('', fontSize: 8)),
        ),
        // Total row
        pw.TableRow(
          children: [
            _buildTableCell('', fontSize: 8),
            _buildTableCell('', fontSize: 8),
            _buildTableCell('', fontSize: 8),
            _buildTableCell('', fontSize: 8),
            _buildTableCell('', fontSize: 8),
            _buildTableCell('', fontSize: 8),
            _buildTableCell('', fontSize: 8),
            _buildTableCell('Total', isHeader: true, fontSize: 8),
            _buildTableCell('', fontSize: 8),
            _buildTableCell(subtotal.toStringAsFixed(2), isHeader: true, fontSize: 8),
            _buildTableCell('', fontSize: 8),
          ],
        ),
      ],
    );
  }
  
  pw.Widget _buildTableCell(String text, {bool isHeader = false, double fontSize = 9, PdfColor? textColor}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: textColor ?? PdfColors.black,
        ),
      ),
    );
  }
  
  pw.Widget _buildAmountInWords(double amount, String currencyCode) {
    final words = NumberToWords.convertToWords(amount, currency: currencyCode);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Text(
        'Amount in words: $words',
        style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
      ),
    );
  }
  
  pw.Widget _buildTermsSection(String terms) {
    // Parse terms into numbered list if needed
    final termsList = terms.split('\n').where((t) => t.trim().isNotEmpty).toList();
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'COMMERCIAL TERMS AND CONDITIONS:',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          // Parse and display terms as numbered list
          ...termsList.map((term) {
            // Check if term already has a number prefix
            final trimmedTerm = term.trim();
            if (trimmedTerm.isEmpty) return pw.SizedBox.shrink();
            
            // If it starts with a number or roman numeral, use as-is, otherwise add numbering
            final hasNumber = RegExp(r'^[iIvVxXlLcCdDmM0-9]+[\.\)]').hasMatch(trimmedTerm);
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                hasNumber ? trimmedTerm : 'i $trimmedTerm',
                style: const pw.TextStyle(fontSize: 9),
              ),
            );
          }),
          // Add default terms if not provided
          if (termsList.isEmpty) ...[
            _buildDefaultTerms(),
          ],
        ],
      ),
    );
  }
  
  pw.Widget _buildDefaultTerms() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('i Prices are Exclusive of VAT - 5%', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('ii Payment Term: As mutually agreed', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('iii Delivery Terms Within UAE : DAP, Outside UAE : Ex-works UAE', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('iv Offer Validity 30 Days', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('v Bank Details', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('A/c TITLE: AL KAREEM ENTERPRISES LLC', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('BANK NAME: National Bank of Fujairah', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('AED Account NO: 012000394988', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('IBAN NO: AE170380000012000394988', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('SWIFT CODE: NBFUAEAFFUJ', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('vi Delivery date is subject to change due to current pandemic situation.', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('vii All other terms and condition to remain', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('viii Scope of work : Supply only', style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }
  
  pw.Widget _buildFooter(PdfDocument document) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 20),
      child: pw.Stack(
        children: [
          // Main content
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Trust to have been of assistance to you with the above information.',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Should you require any further details, please do not hesitate to contact',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'We look forward to receive your valuable order.',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 15),
              // Regards section with seal on the right
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Regards',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          'Syed Rahim / Sales Manager',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Company Seal on the right
                  pw.Container(
                    width: 80,
                    height: 80,
                    child: _buildCompanySeal(document),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
            ],
          ),
        ],
      ),
    );
  }
  
  /// Build company seal/stamp
  pw.Widget _buildCompanySeal(PdfDocument document) {
    return pw.Container(
      width: 80,
      height: 80,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(color: PdfColors.blue700, width: 2),
      ),
      child: pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              'AL KAREEM',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue700,
              ),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'ENTERPRISES',
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue700,
              ),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'LLC.',
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue700,
              ),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'P.O.Box: 2556',
              style: pw.TextStyle(
                fontSize: 6,
                color: PdfColors.blue700,
              ),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 1),
            pw.Text(
              'Fujairah-U.A.E.',
              style: pw.TextStyle(
                fontSize: 6,
                color: PdfColors.blue700,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  /// Build red footer bar with contact details
  pw.Widget _buildFooterBar() {
    return pw.Container(
      color: PdfColors.red700,
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: pw.Wrap(
        alignment: pw.WrapAlignment.center,
        spacing: 10,
        runSpacing: 4,
        children: [
          pw.Text(
            'alkareem@alkareemllc.com',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.white,
            ),
          ),
          pw.Text(
            '|',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.white,
            ),
          ),
          pw.Text(
            'Tel: 09-2241772',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.white,
            ),
          ),
          pw.Text(
            '|',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.white,
            ),
          ),
          pw.Text(
            'Website: www.alkareemllc.com',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.white,
            ),
          ),
        ],
      ),
    );
  }
  
  pw.Widget _buildPendingItemsDisclaimer(Quotation quotation) {
    // Get all pending items
    final pendingItems = quotation.items.where((item) => item.status == 'pending' || item.unitPrice == 0).toList();
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.yellow100,
        border: pw.Border.all(color: PdfColors.orange, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Note: Some items from your inquiry are currently being priced and will be sent in a separate update.',
            style: pw.TextStyle(
              fontSize: 10,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.orange900,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (pendingItems.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              'Pending Items:',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.orange900,
              ),
            ),
            pw.SizedBox(height: 4),
            ...pendingItems.map((item) {
              final itemCode = item.itemCode?.isNotEmpty == true ? item.itemCode! : 'N/A';
              return pw.Padding(
                padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
                child: pw.Text(
                  '• ${item.itemName} (Code: $itemCode)',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontStyle: pw.FontStyle.italic,
                    color: PdfColors.orange900,
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final day = date.day.toString().padLeft(2, '0');
    final month = months[date.month - 1];
    final year = date.year.toString().substring(2); // Last 2 digits
    return '$day-$month-$year';
  }
}

