import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/quotation_provider.dart';
import '../providers/inquiry_provider.dart';
import '../../domain/entities/quotation.dart';
import '../../domain/entities/customer_inquiry.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/email_service.dart';
import '../../data/services/quotation_pdf_service.dart';
import '../../data/services/database_service.dart';

class QuotationDetailScreen extends ConsumerStatefulWidget {
  final String quotationId;

  const QuotationDetailScreen({super.key, required this.quotationId});

  @override
  ConsumerState<QuotationDetailScreen> createState() => _QuotationDetailScreenState();
}

class _QuotationDetailScreenState extends ConsumerState<QuotationDetailScreen> {
  Quotation? _quotation;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _autoSendEmail = true;
  late TextEditingController _recipientEmailController;
  final TextEditingController _ccEmailController = TextEditingController();
  final Map<int, TextEditingController> _itemNameControllers = {};
  final Map<int, TextEditingController> _itemCodeControllers = {};
  final Map<int, TextEditingController> _quantityControllers = {};
  final Map<int, TextEditingController> _unitPriceControllers = {};
  final Map<int, FocusNode> _unitPriceFocusNodes = {};
  final _emailService = EmailService();
  final _pdfService = QuotationPDFService();
  final _databaseService = DatabaseService.instance;

  @override
  void initState() {
    super.initState();
    _recipientEmailController = TextEditingController();
    _loadQuotation();
  }

  @override
  void dispose() {
    _recipientEmailController.dispose();
    _ccEmailController.dispose();
    for (var controller in _itemNameControllers.values) {
      controller.dispose();
    }
    for (var controller in _itemCodeControllers.values) {
      controller.dispose();
    }
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    for (var controller in _unitPriceControllers.values) {
      controller.dispose();
    }
    for (var focusNode in _unitPriceFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _loadQuotation() async {
    setState(() => _isLoading = true);
    final quotation = await ref.read(quotationProvider.notifier).getQuotationById(widget.quotationId);
    
    debugPrint('📧 [Load Quotation] ========================================');
    debugPrint('📧 [Load Quotation] Loading quotation ID: ${widget.quotationId}');
    debugPrint('📧 [Load Quotation] Quotation found: ${quotation != null}');
    
    // Load CC emails from quotation notes if stored there
    List<String> ccEmails = [];
    
    setState(() {
      _quotation = quotation;
      if (quotation != null) {
        debugPrint('📧 [Load Quotation] Quotation number: ${quotation.quotationNumber}');
        debugPrint('📧 [Load Quotation] Notes field value: ${quotation.notes}');
        debugPrint('📧 [Load Quotation] Notes is null: ${quotation.notes == null}');
        debugPrint('📧 [Load Quotation] Notes is empty: ${quotation.notes?.isEmpty ?? true}');
        
        if (quotation.customerEmail != null) {
          _recipientEmailController.text = quotation.customerEmail!;
        }
        
        // Load CC from notes if stored there (format: "CC: email1, email2")
        if (quotation.notes != null && quotation.notes!.isNotEmpty) {
          final notes = quotation.notes!;
          debugPrint('📧 [Load Quotation] Notes content: "$notes"');
          debugPrint('📧 [Load Quotation] Notes length: ${notes.length}');
          debugPrint('📧 [Load Quotation] Contains "CC:": ${notes.contains('CC:')}');
          debugPrint('📧 [Load Quotation] Contains "cc:": ${notes.contains('cc:')}');
          
          // Try multiple patterns to find CC emails
          // Pattern 1: "CC: email1, email2" at the start or anywhere
          if (notes.contains('CC:') || notes.contains('cc:')) {
            // Match "CC:" or "cc:" followed by emails (case insensitive, match until newline or end)
            final ccMatch = RegExp(r'[Cc][Cc]:\s*([^\n]+)', caseSensitive: false).firstMatch(notes);
            if (ccMatch != null) {
              final ccString = ccMatch.group(1)!.trim();
              debugPrint('📧 [Load Quotation] ✅ Found CC string: "$ccString"');
              ccEmails = ccString
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty && e.contains('@'))
                  .toList();
              debugPrint('📧 [Load Quotation] ✅ Extracted CC emails: $ccEmails');
            } else {
              debugPrint('📧 [Load Quotation] ⚠️ Regex match failed, trying line-by-line');
              // Try matching the entire line if it starts with CC:
              final lines = notes.split('\n');
              for (final line in lines) {
                final trimmedLine = line.trim();
                if (trimmedLine.toLowerCase().startsWith('cc:')) {
                  final ccString = trimmedLine.substring(trimmedLine.indexOf(':') + 1).trim();
                  ccEmails = ccString
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty && e.contains('@'))
                      .toList();
                  debugPrint('📧 [Load Quotation] ✅ Found CC from line: "$trimmedLine" -> $ccEmails');
                  break;
                }
              }
            }
          } else {
            debugPrint('📧 [Load Quotation] ⚠️ Notes does not contain "CC:" or "cc:"');
          }
        } else {
          debugPrint('📧 [Load Quotation] ⚠️ Notes is null or empty');
        }
        
        if (ccEmails.isNotEmpty) {
          _ccEmailController.text = ccEmails.join(', ');
          debugPrint('📧 [Load Quotation] ✅ Set CC controller with: ${_ccEmailController.text}');
        } else {
          debugPrint('📧 [Load Quotation] ⚠️ No CC emails found or extracted');
          debugPrint('📧 [Load Quotation] CC controller will remain empty');
        }
        
        // Initialize controllers for items
        for (int i = 0; i < quotation.items.length; i++) {
          final item = quotation.items[i];
          _itemNameControllers[i] = TextEditingController(text: item.itemName);
          _itemCodeControllers[i] = TextEditingController(text: item.itemCode ?? '');
          _quantityControllers[i] = TextEditingController(text: item.quantity.toStringAsFixed(2));
          _unitPriceControllers[i] = TextEditingController(text: item.unitPrice.toStringAsFixed(2));
          
          // Initialize focus node for unit price field (no auto-trigger, only via History button)
          _unitPriceFocusNodes[i] = FocusNode();
        }
      }
      _isLoading = false;
    });
  }

  void _calculateItemTotal(int index) {
    if (_quotation == null || index >= _quotation!.items.length) return;
    
    final quantityText = _quantityControllers[index]?.text ?? '0';
    final priceText = _unitPriceControllers[index]?.text ?? '0';
    final quantity = double.tryParse(quantityText) ?? 0.0;
    final price = double.tryParse(priceText) ?? 0.0;
    
    setState(() {
      // Update the item in the quotation
      final updatedItems = List<QuotationItem>.from(_quotation!.items);
      
      // Update status based on price - if price > 0, set to 'ready', otherwise 'pending'
      final isPriced = price > 0;
      final status = isPriced ? 'ready' : 'pending';
      
      final nameText = (_itemNameControllers[index]?.text ?? '').trim();
      updatedItems[index] = updatedItems[index].copyWith(
        itemName: nameText.isNotEmpty ? nameText : updatedItems[index].itemName,
        quantity: quantity,
        unitPrice: price,
        total: quantity * price,
        itemCode: _itemCodeControllers[index]?.text ?? updatedItems[index].itemCode,
        isPriced: isPriced,
        status: status,
      );
      
      // Recalculate grand total
      final subtotal = updatedItems.fold<double>(0, (sum, item) => sum + item.total);
      final vat = subtotal * 0.05;
      final grandTotal = subtotal + vat;
      
      _quotation = _quotation!.copyWith(
        items: updatedItems,
        totalAmount: grandTotal,
      );
    });
  }

  Future<void> _saveQuotation() async {
    if (_quotation == null) return;

    setState(() => _isSaving = true);

    try {
      // Update items with edited values
      final updatedItems = <QuotationItem>[];
      for (int i = 0; i < _quotation!.items.length; i++) {
        final originalItem = _quotation!.items[i];
        final itemName = _itemNameControllers[i]?.text.trim();
        final quantity = double.tryParse(_quantityControllers[i]?.text ?? '0') ?? originalItem.quantity;
        final unitPrice = double.tryParse(_unitPriceControllers[i]?.text ?? '0') ?? originalItem.unitPrice;
        final itemCode = _itemCodeControllers[i]?.text ?? originalItem.itemCode;
        
        // Update status based on price - if price > 0, set to 'ready', otherwise 'pending'
        final isPriced = unitPrice > 0;
        final status = isPriced ? 'ready' : 'pending';
        
        updatedItems.add(originalItem.copyWith(
          itemName: (itemName != null && itemName.isNotEmpty) ? itemName : originalItem.itemName,
          quantity: quantity,
          unitPrice: unitPrice,
          total: quantity * unitPrice,
          itemCode: itemCode?.isNotEmpty == true ? itemCode : originalItem.itemCode,
          isPriced: isPriced,
          status: status,
        ));
      }
      
      // Recalculate grand total
      final subtotal = updatedItems.fold<double>(0, (sum, item) => sum + item.total);
      final vat = subtotal * 0.05;
      final grandTotal = subtotal + vat;
      
      // Update quotation with email from controller
      final updatedQuotation = _quotation!.copyWith(
        items: updatedItems,
        totalAmount: grandTotal,
        customerEmail: _recipientEmailController.text.trim().isNotEmpty
            ? _recipientEmailController.text.trim()
            : _quotation!.customerEmail,
        updatedAt: DateTime.now(),
      );

      // Update quotation in database
      await ref.read(quotationProvider.notifier).updateQuotation(updatedQuotation);

      // Auto-send email if enabled and recipient email is available
      bool emailSent = false;
      final recipientEmail = _recipientEmailController.text.trim();
      debugPrint('📧 Preparing to send quotation email to: $recipientEmail');

      if (_autoSendEmail && recipientEmail.isNotEmpty) {
        try {
          // Check if there are pending items
          final hasPendingItems = updatedQuotation.items.any((item) => item.status == 'pending');
          
          // Generate quotation PDF file - use partial PDF if there are pending items
          final pdfBytes = hasPendingItems
              ? await _pdfService.generatePartialQuotePDF(updatedQuotation)
              : await _pdfService.generateQuotationPDF(updatedQuotation);

          // Prepare items data for email body - only include ready items
          final readyItems = updatedQuotation.items.where((item) => item.status == 'ready').toList();
          final itemsData = readyItems.map((item) => {
            'itemName': item.itemName,
            'quantity': item.quantity,
            'unit': item.unit,
            'unitPrice': item.unitPrice,
            'total': item.total,
          }).toList();
          
          // Prepare pending items data for email body
          final pendingItemsList = updatedQuotation.items.where((item) => item.status == 'pending' || item.unitPrice == 0).toList();
          final pendingItemsData = pendingItemsList.map((item) => {
            'itemName': item.itemName,
            'itemCode': item.itemCode ?? 'N/A',
          }).toList();
          
          // Calculate grand total from ready items only
          final readySubtotal = readyItems.fold<double>(0.0, (sum, item) => sum + item.total);
          final readyVat = readySubtotal * 0.05;
          final readyGrandTotal = readySubtotal + readyVat;

          // Parse CC emails
          final ccEmails = _ccEmailController.text
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          
          // Extract threadId, originalMessageId, and originalSubject from notes for reply threading
          String? threadId;
          String? originalMessageId;
          String? originalSubject;
          
          if (updatedQuotation.notes != null && updatedQuotation.notes!.isNotEmpty) {
            final notes = updatedQuotation.notes!;
            debugPrint('📧 [Send Quotation] Extracting thread info from notes: $notes');
            
            // Extract THREAD_ID (REQUIRED for Gmail API reply threading)
            final threadIdMatch = RegExp(r'THREAD_ID:\s*([^\n]+)').firstMatch(notes);
            if (threadIdMatch != null) {
              threadId = threadIdMatch.group(1)?.trim();
              debugPrint('📧 [Send Quotation] ✅ Found threadId: $threadId');
            }
            
            // Extract ORIGINAL_MESSAGE_ID (for In-Reply-To header)
            final messageIdMatch = RegExp(r'ORIGINAL_MESSAGE_ID:\s*([^\n]+)').firstMatch(notes);
            if (messageIdMatch != null) {
              originalMessageId = messageIdMatch.group(1)?.trim();
              debugPrint('📧 [Send Quotation] ✅ Found originalMessageId: $originalMessageId');
            }
            
            // Extract ORIGINAL_SUBJECT
            final subjectMatch = RegExp(r'ORIGINAL_SUBJECT:\s*([^\n]+)').firstMatch(notes);
            if (subjectMatch != null) {
              originalSubject = subjectMatch.group(1)?.trim();
              debugPrint('📧 [Send Quotation] ✅ Found originalSubject: $originalSubject');
            }
          }
          
          // Verify we have threadId for reply (required)
          if (threadId == null || threadId.isEmpty) {
            debugPrint('⚠️ [Send Quotation] WARNING: No threadId found! Email will be sent as NEW email, not reply!');
          } else {
            debugPrint('📧 [Send Quotation] ✅ Reply threading enabled - will reply to thread: $threadId');
          }
          
          // Send email as reply to original thread if threadId exists
          emailSent = await _emailService.sendQuotationEmail(
            to: recipientEmail,
            quotationNumber: updatedQuotation.quotationNumber,
            quotationPdf: pdfBytes,
            customerName: updatedQuotation.customerName,
            items: itemsData,
            grandTotal: hasPendingItems ? readyGrandTotal : updatedQuotation.totalAmount,
            currency: updatedQuotation.currency,
            cc: ccEmails.isNotEmpty ? ccEmails : null,
            threadId: threadId, // Pass threadId for reply threading (REQUIRED for Gmail API)
            originalMessageId: originalMessageId, // Pass original message ID for In-Reply-To header
            originalSubject: originalSubject, // Pass original subject for reply
            pendingItems: hasPendingItems ? pendingItemsData : null, // Pass pending items for email body
          );

          if (emailSent) {
            // Update quotation status to 'sent'
            final sentQuotation = updatedQuotation.copyWith(status: 'sent');
            await ref.read(quotationProvider.notifier).updateQuotation(sentQuotation);

            // Item-level status: update inquiry items — quoted where price > 0, pending otherwise
            if (updatedQuotation.inquiryId != null &&
                updatedQuotation.inquiryId!.isNotEmpty) {
              final inquiry =
                  await ref.read(inquiryProvider.notifier).getInquiryById(updatedQuotation.inquiryId!);
              if (inquiry != null && inquiry.items.isNotEmpty) {
                final qItems = updatedQuotation.items;
                final updatedItems = <InquiryItem>[];
                for (int i = 0; i < inquiry.items.length; i++) {
                  final inqItem = inquiry.items[i];
                  final qItem = i < qItems.length ? qItems[i] : null;
                  final isQuoted = qItem != null && (qItem.unitPrice > 0);
                  updatedItems.add(
                    inqItem.copyWith(status: isQuoted ? 'quoted' : 'pending'),
                  );
                }
                final quotedCount = updatedItems.where((e) => e.status == 'quoted').length;
                final pendingCount = updatedItems.length - quotedCount;
                final inquiryStatus = pendingCount == 0
                    ? 'quoted'
                    : quotedCount == 0
                        ? 'pending'
                        : 'partially_quoted';
                await ref.read(inquiryProvider.notifier).updateInquiry(
                      inquiry.copyWith(items: updatedItems, status: inquiryStatus),
                    );
              }
            }
            
            // Reload quotation to reflect changes
            await _loadQuotation();

            // Show success message with email address
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Quotation Sent Successfully',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Sent to: $recipientEmail',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 5),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          } else {
            // Email sending failed
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Quotation saved but email sending failed'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 5),
                ),
              );
            }
          }
        } catch (e) {
          debugPrint('Error sending quotation email: $e');
          // Don't fail the whole operation if email fails
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Quotation saved but email failed: $e'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }

      // Show success message (only if email wasn't already sent above)
      if (mounted && !emailSent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Quotation saved successfully'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Redirect to home/dashboard after successful save
      if (mounted) {
        // Small delay to show success message
        await Future.delayed(const Duration(milliseconds: 500));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  /// Show historical data bottom sheet when Unit Price field is focused
  Future<void> _showHistoricalDataDialog(int index) async {
    debugPrint('🚀 [Unit Price Focus] _showHistoricalDataDialog CALLED for index: $index');
    
    if (_quotation == null) {
      debugPrint('⚠️ [Unit Price Focus] _quotation is null');
      return;
    }
    
    if (index >= _quotation!.items.length) {
      debugPrint('⚠️ [Unit Price Focus] Invalid index: $index, items length: ${_quotation!.items.length}');
      return;
    }
    
    final item = _quotation!.items[index];
    final materialCode = (_itemCodeControllers[index]?.text ?? item.itemCode ?? '').trim();
    
    debugPrint('🔍 [Unit Price Focus] Checking historical quotations for Material Code: "$materialCode"');
    
    if (materialCode.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter Material Code first to view historical data'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    
    try {
      debugPrint('📊 [Unit Price Focus] Starting database query...');
      final historicalQuotations = await _databaseService.getHistoricalQuotationsByMaterialCode(
        materialCode: materialCode,
        limit: 10,
      );
      
      debugPrint('✅ [Unit Price Focus] Found ${historicalQuotations.length} quotations for Material Code: $materialCode');
      
      if (!mounted) return;
      
      if (historicalQuotations.isEmpty) {
        if (mounted) {
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => Container(
              height: MediaQuery.of(context).size.height * 0.4,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Price History - Material Code: $materialCode',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No historical quotations found',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No previous quotations found for Material Code: $materialCode',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return;
      }
      
      final List<Map<String, dynamic>> quotationData = [];
      for (final qtn in historicalQuotations) {
        final qtnItem = qtn.items.firstWhere(
          (i) => i.itemCode?.toLowerCase().trim() == materialCode.toLowerCase().trim(),
          orElse: () => qtn.items.first,
        );
        
        final linkedPOs = await _databaseService.getPurchaseOrdersByQuotation(
          quotationNumber: qtn.quotationNumber,
          quotationId: qtn.id,
        );
        
        quotationData.add({
          'quotation': qtn,
          'item': qtnItem,
          'poNumbers': linkedPOs.map((po) => po.poNumber).toList(),
        });
      }
      
      if (!mounted) return;
      
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Price History - Material Code: $materialCode',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: quotationData.length,
                  itemBuilder: (context, idx) {
                    final data = quotationData[idx];
                    final qtn = data['quotation'] as Quotation;
                    final qtnItem = data['item'] as QuotationItem;
                    final poNumbers = data['poNumbers'] as List<String>;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      child: InkWell(
                        onTap: () {
                          _unitPriceControllers[index]?.text = qtnItem.unitPrice.toStringAsFixed(2);
                          _calculateItemTotal(index);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Price copied: ${CurrencyHelper.formatAmount(qtnItem.unitPrice, qtn.currency ?? 'AED')}'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Quote: ${qtn.quotationNumber}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          CurrencyHelper.formatAmount(qtnItem.unitPrice, qtn.currency ?? 'AED'),
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.content_copy),
                                    onPressed: () {
                                      _unitPriceControllers[index]?.text = qtnItem.unitPrice.toStringAsFixed(2);
                                      _calculateItemTotal(index);
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Price copied: ${CurrencyHelper.formatAmount(qtnItem.unitPrice, qtn.currency ?? 'AED')}'),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    tooltip: 'Use this price',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Divider(color: Colors.grey[300]),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text(
                                    DateFormat('MMM dd, yyyy').format(qtn.quotationDate),
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                  const SizedBox(width: 16),
                                  Icon(Icons.business, size: 16, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      qtn.customerName,
                                      style: TextStyle(color: Colors.grey[600]),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.description, size: 16, color: Colors.green[700]),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: poNumbers.isEmpty
                                        ? Text(
                                            'PO: —',
                                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                          )
                                        : Wrap(
                                            spacing: 4,
                                            runSpacing: 4,
                                            children: poNumbers.map((poNumber) {
                                              return Chip(
                                                label: Text(
                                                  'PO: $poNumber',
                                                  style: const TextStyle(fontSize: 12),
                                                ),
                                                backgroundColor: Colors.green[50],
                                                labelStyle: TextStyle(color: Colors.green[900]),
                                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                              );
                                            }).toList(),
                                          ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ [Unit Price Focus] Error fetching historical data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading historical data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteQuotation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Quotation'),
        content: const Text('Are you sure you want to delete this quotation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && _quotation != null) {
      await ref.read(quotationProvider.notifier).deleteQuotation(_quotation!.id!);
      if (mounted) {
        context.pop();
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'quote ready':
        return Colors.green;
      case 'sent':
        return Colors.blue;
      case 'expired':
        return Colors.orange;
      case 'pending':
        return Colors.yellow;
      case 'draft':
      default:
        return Colors.grey;
    }
  }
  
  bool _shouldShowStatusChip(String status) {
    final lowerStatus = status.toLowerCase();
    // Hide Accepted and Rejected chips
    if (lowerStatus == 'accepted' || lowerStatus == 'rejected') {
      return false;
    }
    return true;
  }
  
  /// Check if quotation has any pending items
  bool _hasPendingItems() {
    if (_quotation == null) return false;
    return _quotation!.items.any((item) => item.status == 'pending' || item.unitPrice == 0);
  }

  /// True when at least one item has unit price > 0 (from current controllers or items).
  /// Used to enable "Send Quotation" button.
  bool _hasAtLeastOnePricedItem() {
    if (_quotation == null || _quotation!.items.isEmpty) return false;
    for (int i = 0; i < _quotation!.items.length; i++) {
      final priceText = _unitPriceControllers[i]?.text.trim();
      final price = double.tryParse(priceText ?? '') ?? _quotation!.items[i].unitPrice;
      if (price > 0) return true;
    }
    return false;
  }
  
  /// Check if send button should be shown
  /// Show button if: 
  /// - Status is not 'sent' (normal case), OR
  /// - Status is 'sent' and there are pending items (allows sending updates for pending items), OR
  /// - Status is 'sent' and all items are ready (allows sending final complete quotation)
  /// This ensures button shows when user enters prices for pending items
  bool _shouldShowSendButton() {
    if (_quotation == null) return false;
    final status = _quotation!.status.toLowerCase();
    final hasPending = _hasPendingItems();
    final allItemsReady = _quotation!.items.isNotEmpty && !hasPending;
    
    // Show if not sent, OR if sent and has pending items (to send update), OR if sent and all ready (to send final)
    if (status != 'sent') {
      return true; // Always show for non-sent quotations
    }
    
    // For sent quotations, show if there are pending items or all items are ready
    return hasPending || allItemsReady;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quotation Detail')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_quotation == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quotation Detail')),
        body: const Center(
          child: Text('Quotation not found'),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final scaffoldBg = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _quotation!.quotationNumber,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _deleteQuotation,
            tooltip: 'Delete quotation',
          ),
        ],
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderCard(context, surfaceColor),
            const SizedBox(height: 20),
            _buildCustomerCard(context, surfaceColor),
            const SizedBox(height: 20),
            _buildItemsCard(context, surfaceColor),
            const SizedBox(height: 20),
            _buildSummaryCard(context, surfaceColor),
            if (_quotation!.terms != null || _quotation!.notes != null) ...[
              const SizedBox(height: 20),
              _buildTermsCard(context, surfaceColor),
            ],
            const SizedBox(height: 20),
            _buildEmailOptionsCard(context, surfaceColor),
            const SizedBox(height: 20),
            if (_shouldShowSendButton())
              _buildSendQuotationButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailOptionsCard(BuildContext context, Color surfaceColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _ModernSectionCard(
      surfaceColor: surfaceColor,
      icon: Icons.mail_outline_rounded,
      title: 'Email Options',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _recipientEmailController,
            decoration: InputDecoration(
              labelText: 'Send To',
              hintText: 'Enter recipient email address',
              prefixIcon: Icon(Icons.email_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
              filled: true,
              fillColor: isDark ? surfaceColor : Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
              ),
              helperText: 'Email address for sending quotation. You can edit if needed.',
              helperStyle: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              suffixIcon: _recipientEmailController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded, size: 20, color: Colors.grey.shade600),
                      onPressed: () => setState(() => _recipientEmailController.clear()),
                    )
                  : null,
            ),
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ccEmailController,
            decoration: InputDecoration(
              labelText: 'CC (comma-separated)',
              hintText: 'email1@example.com, email2@example.com',
              prefixIcon: Icon(Icons.alternate_email_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
              filled: true,
              fillColor: isDark ? surfaceColor : Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
              ),
              helperText: 'Enter CC email addresses separated by commas',
              helperStyle: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white12 : Colors.grey.shade50).withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              title: Text(
                'Automatically send quotation via email',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
              ),
              subtitle: _recipientEmailController.text.isNotEmpty
                  ? Text(
                      'Will send to: ${_recipientEmailController.text}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    )
                  : Text(
                      'Recipient email not set',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
              value: _autoSendEmail && _recipientEmailController.text.isNotEmpty,
              onChanged: _recipientEmailController.text.isNotEmpty
                  ? (value) => setState(() => _autoSendEmail = value)
                  : null,
              activeColor: Theme.of(context).colorScheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context, Color surfaceColor) {
    return _ModernSectionCard(
      surfaceColor: surfaceColor,
      icon: Icons.description_outlined,
      title: 'Quotation Details',
      trailing: _hasPendingItems()
          ? _StatusChip(label: 'Pending', color: AppTheme.warningOrange)
          : (_shouldShowStatusChip(_quotation!.status)
              ? _StatusChip(label: _quotation!.status, color: _getStatusColor(_quotation!.status))
              : null),
      child: Column(
        children: [
          _buildInfoRow(context, 'Quotation Number', _quotation!.quotationNumber),
          _buildInfoRow(context, 'Quotation Date',
              '${_quotation!.quotationDate.day}/${_quotation!.quotationDate.month}/${_quotation!.quotationDate.year}'),
          _buildInfoRow(context, 'Valid Until',
              '${_quotation!.validityDate.day}/${_quotation!.validityDate.month}/${_quotation!.validityDate.year}'),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(BuildContext context, Color surfaceColor) {
    return _ModernSectionCard(
      surfaceColor: surfaceColor,
      icon: Icons.person_outline_rounded,
      title: 'Customer Information',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _quotation!.customerName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
          ),
          if (_quotation!.customerAddress != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_outlined, size: 18, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _quotation!.customerAddress!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ],
          if (_quotation!.customerEmail != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.email_outlined, size: 18, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _quotation!.customerEmail!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ],
          if (_quotation!.customerPhone != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 18, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  _quotation!.customerPhone!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsCard(BuildContext context, Color surfaceColor) {
    return _ModernSectionCard(
      surfaceColor: surfaceColor,
      icon: Icons.inventory_2_outlined,
      title: 'Items',
      child: Column(
        children: _quotation!.items.asMap().entries.map((entry) {
          final isLast = entry.key == _quotation!.items.length - 1;
          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: _buildItemRow(context, entry.value, entry.key, surfaceColor),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildItemRow(BuildContext context, QuotationItem item, int index, Color surfaceColor) {
    final currencyCode = _quotation!.currency ?? 'AED';
    final currencySymbol = CurrencyHelper.getCurrencySymbol(currencyCode);
    final isPending = item.status == 'pending' || item.unitPrice == 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? surfaceColor : Colors.grey.shade50;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPending ? (isDark ? Colors.orange.shade900.withOpacity(0.2) : Colors.amber.shade50) : (isDark ? Colors.white.withOpacity(0.05) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPending ? Colors.orange.shade200 : (isDark ? Colors.white12 : Colors.grey.shade200),
          width: 1,
        ),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _itemNameControllers[index],
                  decoration: InputDecoration(
                    labelText: 'Item Name',
                    filled: true,
                    fillColor: fieldBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    isDense: true,
                  ),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                  onChanged: (_) => _calculateItemTotal(index),
                ),
              ),
              if (isPending)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.warningOrange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.warningOrange.withOpacity(0.5)),
                  ),
                  child: Text(
                    'Pending',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.warningOrange),
                  ),
                ),
            ],
          ),
          if (item.description != null) ...[
            const SizedBox(height: 6),
            Text(
              item.description!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _itemCodeControllers[index],
            decoration: InputDecoration(
              labelText: 'Material Code',
              filled: true,
              fillColor: fieldBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              isDense: true,
            ),
            onChanged: (_) => _calculateItemTotal(index),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantityControllers[index],
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    suffixText: item.unit,
                    filled: true,
                    fillColor: fieldBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _calculateItemTotal(index),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _unitPriceControllers[index],
                  focusNode: _unitPriceFocusNodes[index],
                  decoration: InputDecoration(
                    labelText: 'Unit Price',
                    prefixText: '$currencySymbol ',
                    filled: true,
                    fillColor: fieldBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _calculateItemTotal(index),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                debugPrint('🔘 [History Button] Button pressed for index: $index');
                _showHistoricalDataDialog(index);
              },
              icon: Icon(Icons.history_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
              label: Text(
                'View Price History',
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
              Text(
                CurrencyHelper.formatAmount(item.total, currencyCode),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isPending ? Colors.grey : Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          if (isPending) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.warningOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.warningOrange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.warningOrange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Price pending - Enter unit price to complete this item',
                      style: TextStyle(fontSize: 12, color: AppTheme.warningOrange, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, Color surfaceColor) {
    final currencyCode = _quotation!.currency ?? 'AED';
    final hasPendingItems = _quotation!.items.any((item) => item.status == 'pending' || item.unitPrice == 0);
    final readyItems = _quotation!.items.where((item) => item.status == 'ready' && item.unitPrice > 0).toList();
    final readySubtotal = readyItems.fold<double>(0.0, (sum, item) => sum + item.total);
    final readyVat = readySubtotal * 0.05;
    final readyGrandTotal = readySubtotal + readyVat;

    return _ModernSectionCard(
      surfaceColor: surfaceColor,
      icon: Icons.receipt_long_outlined,
      title: 'Summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPendingItems) ...[
            _buildSummaryRow(context, 'Subtotal (Ready Items)', CurrencyHelper.formatAmount(readySubtotal, currencyCode)),
            const SizedBox(height: 6),
            _buildSummaryRow(context, 'VAT (5%)', CurrencyHelper.formatAmount(readyVat, currencyCode)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.warningOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.warningOrange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 20, color: AppTheme.warningOrange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Partial Quotation - Some items are pending pricing',
                      style: TextStyle(fontSize: 12, color: AppTheme.warningOrange, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  hasPendingItems ? 'Grand Total (Ready Items)' : 'Grand Total',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                Text(
                  CurrencyHelper.formatAmount(hasPendingItems ? readyGrandTotal : _quotation!.totalAmount, currencyCode),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildTermsCard(BuildContext context, Color surfaceColor) {
    return _ModernSectionCard(
      surfaceColor: surfaceColor,
      icon: Icons.note_alt_outlined,
      title: 'Notes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_quotation!.terms != null) ...[
            Text(
              'Terms & Conditions',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _quotation!.terms!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
            if (_quotation!.notes != null) const SizedBox(height: 16),
          ],
          if (_quotation!.notes != null) ...[
            Text(
              'Notes',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
            ),
            if (_quotation!.terms != null) const SizedBox(height: 4),
            Text(
              _quotation!.notes!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendQuotationButton(BuildContext context) {
    final canSend = _hasAtLeastOnePricedItem();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: (_isSaving || !canSend) ? null : () async { await _sendQuotation(); },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: canSend ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
            borderRadius: BorderRadius.circular(16),
            boxShadow: canSend
                ? [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isSaving)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              else
                const Icon(Icons.send_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Text(
                'Send Quotation',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendQuotation() async {
    if (_quotation == null) return;

    setState(() => _autoSendEmail = true);
    await _saveQuotation();
  }
}

/// Modern section card with icon, optional trailing, and consistent padding.
class _ModernSectionCard extends StatelessWidget {
  final Color surfaceColor;
  final IconData icon;
  final String title;
  final Widget? trailing;
  final Widget child;

  const _ModernSectionCard({
    required this.surfaceColor,
    required this.icon,
    required this.title,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Pill-style status chip for quotation status.
class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

