import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/inquiry_provider.dart';
import '../providers/quotation_provider.dart';
import '../../domain/entities/customer_inquiry.dart';
import '../../domain/entities/quotation.dart';
import '../../core/utils/currency_helper.dart';
import '../../data/services/email_service.dart';
import '../../data/services/catalog_service.dart';
import '../../data/services/quotation_pdf_service.dart';
import '../../data/services/quotation_number_service.dart';
import '../../data/services/database_service.dart';

class CreateQuotationScreen extends ConsumerStatefulWidget {
  final String inquiryId;

  const CreateQuotationScreen({super.key, required this.inquiryId});

  @override
  ConsumerState<CreateQuotationScreen> createState() => _CreateQuotationScreenState();
}

class _CreateQuotationScreenState extends ConsumerState<CreateQuotationScreen> {
  CustomerInquiry? _inquiry;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _autoSendEmail = true;
  final Map<int, TextEditingController> _priceControllers = {};
  final Map<int, TextEditingController> _totalControllers = {};
  final Map<int, FocusNode> _priceFocusNodes = {};
  final Map<int, bool> _hasTriggeredDialog = {}; // Track if dialog was shown for each field
  late TextEditingController _recipientEmailController;
  String _currency = 'AED';
  String? _terms;
  String? _notes;
  DateTime _validityDate = DateTime.now().add(const Duration(days: 30));
  final _emailService = EmailService();
  final _catalogService = CatalogService();
  final _pdfService = QuotationPDFService();
  final _quotationNumberService = QuotationNumberService(DatabaseService.instance);
  final _databaseService = DatabaseService.instance;
  bool _allItemsMatched = false;
  final Map<int, TextEditingController> _quantityControllers = {};
  final Map<int, TextEditingController> _materialCodeControllers = {};
  List<String> _ccRecipients = [];
  String? _emailThreadId;
  String? _originalEmailSubject;

  @override
  void initState() {
    super.initState();
    _recipientEmailController = TextEditingController();
    _loadInquiry();
  }

  @override
  void dispose() {
    for (var controller in _priceControllers.values) {
      controller.dispose();
    }
    for (var controller in _totalControllers.values) {
      controller.dispose();
    }
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    for (var controller in _materialCodeControllers.values) {
      controller.dispose();
    }
    for (var focusNode in _priceFocusNodes.values) {
      focusNode.dispose();
    }
    _recipientEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadInquiry() async {
    setState(() => _isLoading = true);
    final inquiry = await ref.read(inquiryProvider.notifier).getInquiryById(widget.inquiryId);
    
    // Debug: Check what email fields are available
    if (inquiry != null) {
      debugPrint('📧 Inquiry loaded - senderEmail: ${inquiry.senderEmail}, customerEmail: ${inquiry.customerEmail}');
    }
    
    setState(() {
      _inquiry = inquiry;
      if (inquiry != null) {
        int matchedCount = 0;
        for (int i = 0; i < inquiry.items.length; i++) {
          final item = inquiry.items[i];
          
          // Initialize quantity and material code controllers
          _quantityControllers[i] = TextEditingController(
            text: item.quantity.toStringAsFixed(2),
          );
          _materialCodeControllers[i] = TextEditingController(
            text: item.itemCode ?? '',
          );
          
          // Initialize focus node for price field
          _priceFocusNodes[i] = FocusNode();
          _hasTriggeredDialog[i] = false;
          print('✅✅✅ [Init] Created FocusNode for field $i');
          debugPrint('✅✅✅ [Init] Created FocusNode for field $i');
          print('FocusNode key: ${_priceFocusNodes[i]?.hashCode}');
          
          // Add listener with comprehensive debugging
          _priceFocusNodes[i]!.addListener(() {
            final hasFocus = _priceFocusNodes[i]!.hasFocus;
            print('========================================');
            print('🎯🎯🎯 [Focus Listener] Field $i - hasFocus: $hasFocus');
            print('Current _hasTriggeredDialog[$i]: ${_hasTriggeredDialog[i]}');
            print('Mounted: $mounted');
            print('========================================');
            debugPrint('🎯 [Focus Listener] Focus changed for field $i, hasFocus: $hasFocus');
            
            if (hasFocus && !(_hasTriggeredDialog[i] ?? false)) {
              _hasTriggeredDialog[i] = true;
              print('🎯🎯🎯 [Focus Listener] Triggering dialog for field $i');
              debugPrint('🎯 [Focus Listener] Unit Price field ${i} gained focus - triggering dialog');
              // Show historical data immediately when field gains focus
              Future.delayed(const Duration(milliseconds: 150), () {
                print('🎯 [Focus Listener] Delayed callback executing...');
                print('Mounted: $mounted');
                print('HasFocus: ${_priceFocusNodes[i]?.hasFocus}');
                if (mounted && _priceFocusNodes[i]?.hasFocus == true) {
                  print('🎯🎯🎯 [Focus Listener] Calling _showHistoricalDataDialog($i)');
                  _showHistoricalDataDialog(i);
                } else {
                  print('⚠️ [Focus Listener] Widget unmounted or focus lost, not showing dialog');
                }
              });
            } else if (!hasFocus) {
              _hasTriggeredDialog[i] = false; // Reset when focus is lost
              print('🎯 [Focus Listener] Field $i lost focus, resetting trigger flag');
            }
          });
          
          print('✅ [Init] FocusNode listener attached for field $i');
          
          // Match item to catalog
          final unitPrice = _catalogService.matchItemPrice(
            item.itemName,
            description: item.description,
          );
          
          // Calculate line total
          final lineTotal = unitPrice * item.quantity;
          
          _priceControllers[i] = TextEditingController(
            text: unitPrice > 0 ? unitPrice.toStringAsFixed(2) : '',
          );
          _totalControllers[i] = TextEditingController(
            text: lineTotal > 0 ? lineTotal.toStringAsFixed(2) : '',
          );
          
          if (unitPrice > 0) {
            matchedCount++;
          }
        }
        
        // Check if all items were matched
        _allItemsMatched = matchedCount == inquiry.items.length && inquiry.items.isNotEmpty;
        
        // Initialize recipient email: prefer customerEmail, then fall back to senderEmail
        // customerEmail is the email extracted from the inquiry document
        // senderEmail is the email address of the person who sent the inquiry email
        // We want to show the customer email in the "Send To:" field
        final customerEmail = inquiry.customerEmail;
        final senderEmail = inquiry.senderEmail;
        
        debugPrint('📧 Inquiry Email Fields - senderEmail: $senderEmail, customerEmail: $customerEmail');
        
        // Prefer customerEmail if available, otherwise use senderEmail
        String? recipientEmail;
        if (customerEmail != null && customerEmail.isNotEmpty) {
          recipientEmail = customerEmail;
          debugPrint('✅ Setting Send To field with customerEmail: $customerEmail');
        } else if (senderEmail != null && senderEmail.isNotEmpty) {
          recipientEmail = senderEmail;
          debugPrint('✅ Setting Send To field with senderEmail: $senderEmail');
        }
        
        // Set the email in the controller (even if it matches account email, user can edit)
        if (recipientEmail != null && recipientEmail.isNotEmpty) {
          _recipientEmailController.text = recipientEmail;
        } else {
          debugPrint('⚠️ No customer email found. User can enter manually.');
          _recipientEmailController.text = '';
        }
      }
      _isLoading = false;
    });
  }

  void _calculateTotal(int index) {
    if (_inquiry == null || index >= _inquiry!.items.length) return;
    
    final priceText = _priceControllers[index]?.text ?? '0';
    final quantityText = _quantityControllers[index]?.text ?? _inquiry!.items[index].quantity.toString();
    final price = double.tryParse(priceText) ?? 0.0;
    final quantity = double.tryParse(quantityText) ?? _inquiry!.items[index].quantity;
    final lineTotal = price * quantity; // Calculate line total
    
    _totalControllers[index]?.text = lineTotal.toStringAsFixed(2);
    
    // Update matched status
    final allMatched = _inquiry!.items.asMap().entries.every((entry) {
      final idx = entry.key;
      final priceText = _priceControllers[idx]?.text ?? '0';
      final price = double.tryParse(priceText) ?? 0.0;
      return price > 0;
    });
    _allItemsMatched = allMatched && _inquiry!.items.isNotEmpty;
    
    setState(() {});
  }

  double _calculateGrandTotal() {
    double subtotal = 0.0;
    for (int i = 0; i < (_inquiry?.items.length ?? 0); i++) {
      final totalText = _totalControllers[i]?.text ?? '0';
      subtotal += double.tryParse(totalText) ?? 0.0;
    }
    
    // Add 5% VAT
    final vat = subtotal * 0.05;
    final grandTotal = subtotal + vat;
    
    return grandTotal;
  }
  
  double _calculateSubtotal() {
    double subtotal = 0.0;
    for (int i = 0; i < (_inquiry?.items.length ?? 0); i++) {
      final totalText = _totalControllers[i]?.text ?? '0';
      subtotal += double.tryParse(totalText) ?? 0.0;
    }
    return subtotal;
  }
  
  double _calculateVAT() {
    return _calculateSubtotal() * 0.05;
  }

  /// Show historical data bottom sheet when Unit Price field is focused
  Future<void> _showHistoricalDataDialog(int index) async {
    print('========================================');
    print('🚀🚀🚀🚀🚀 _showHistoricalDataDialog CALLED');
    print('Index: $index');
    print('Timestamp: ${DateTime.now()}');
    print('Mounted: $mounted');
    print('_inquiry is null: ${_inquiry == null}');
    if (_inquiry != null) {
      print('Items length: ${_inquiry!.items.length}');
    }
    print('========================================');
    debugPrint('🚀🚀🚀 [Unit Price Focus] _showHistoricalDataDialog CALLED for index: $index');
    
    if (_inquiry == null) {
      debugPrint('⚠️ [Unit Price Focus] _inquiry is null');
      print('⚠️ [Unit Price Focus] _inquiry is null');
      return;
    }
    
    if (index >= _inquiry!.items.length) {
      debugPrint('⚠️ [Unit Price Focus] Invalid index: $index, items length: ${_inquiry!.items.length}');
      print('⚠️ [Unit Price Focus] Invalid index: $index, items length: ${_inquiry!.items.length}');
      return;
    }
    
    final item = _inquiry!.items[index];
    final materialCode = (_materialCodeControllers[index]?.text ?? item.itemCode ?? '').trim();
    
    debugPrint('🔍 [Unit Price Focus] Checking historical quotations for Material Code: "$materialCode"');
    print('🔍 [Unit Price Focus] Checking historical quotations for Material Code: "$materialCode"');
    debugPrint('🔍 [Unit Price Focus] Material Code length: ${materialCode.length}');
    debugPrint('🔍 [Unit Price Focus] Material Code from controller: "${_materialCodeControllers[index]?.text}"');
    debugPrint('🔍 [Unit Price Focus] Material Code from item: "${item.itemCode}"');
    
    if (materialCode.isEmpty) {
      // Show message that material code is required
      debugPrint('⚠️ [Unit Price Focus] Material Code is empty');
      print('⚠️ [Unit Price Focus] Material Code is empty');
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
    
    // Fetch historical quotations by Material Code only (all customers)
    try {
      debugPrint('📊 [Unit Price Focus] Starting database query...');
      final historicalQuotations = await _databaseService.getHistoricalQuotationsByMaterialCode(
        materialCode: materialCode,
        limit: 10,
      );
      
      debugPrint('✅ [Unit Price Focus] Found ${historicalQuotations.length} quotations for Material Code: $materialCode');
      
      if (!mounted) {
        debugPrint('⚠️ [Unit Price Focus] Widget not mounted, returning');
        return;
      }
      
      // Always show bottom sheet, even if no quotations found
      debugPrint('📱 [Unit Price Focus] Showing bottom sheet...');
      
      // If no quotations found, show a message but still show the bottom sheet
      if (historicalQuotations.isEmpty) {
        debugPrint('ℹ️ [Unit Price Focus] No historical quotations found for Material Code: $materialCode');
        // Show bottom sheet with "no data" message
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
                            Icon(
                              Icons.history,
                              size: 64,
                              color: Colors.grey[400],
                            ),
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
                              style: TextStyle(
                                color: Colors.grey[600],
                              ),
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
      
      // Fetch PO numbers for each quotation
      final List<Map<String, dynamic>> quotationData = [];
      for (final qtn in historicalQuotations) {
        debugPrint('🔍 [Unit Price Focus] Checking PO for Quotation: ${qtn.quotationNumber}');
        
        // Find the matching item in the quotation
        final qtnItem = qtn.items.firstWhere(
          (i) => i.itemCode?.toLowerCase() == materialCode.toLowerCase(),
          orElse: () => qtn.items.first,
        );
        
        // Get POs linked to this quotation
        final linkedPOs = await _databaseService.getPurchaseOrdersByQuotation(
          quotationNumber: qtn.quotationNumber,
          quotationId: qtn.id,
        );
        
        debugPrint('✅ [Unit Price Focus] Quotation ${qtn.quotationNumber} - PO Count: ${linkedPOs.length}');
        if (linkedPOs.isNotEmpty) {
          debugPrint('📋 [Unit Price Focus] PO Numbers: ${linkedPOs.map((po) => po.poNumber).join(", ")}');
        } else {
          debugPrint('ℹ️ [Unit Price Focus] No PO found for Quotation: ${qtn.quotationNumber}');
        }
        
        quotationData.add({
          'quotation': qtn,
          'item': qtnItem,
          'poNumbers': linkedPOs.map((po) => po.poNumber).toList(),
        });
      }
      
      // Show bottom sheet with historical data
      if (!mounted) {
        debugPrint('⚠️ [Unit Price Focus] Widget not mounted, cannot show bottom sheet');
        return;
      }
      
      debugPrint('📱 [Unit Price Focus] Showing bottom sheet with ${quotationData.length} quotations');
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
                // Header
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
                // Content
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
                            // Copy amount to current field
                            _priceControllers[index]?.text = qtnItem.unitPrice.toStringAsFixed(2);
                            _calculateTotal(index);
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Price copied: ${CurrencyHelper.formatAmount(qtnItem.unitPrice, qtn.currency)}'),
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
                                        _priceControllers[index]?.text = qtnItem.unitPrice.toStringAsFixed(2);
                                        _calculateTotal(index);
                                        Navigator.pop(context);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Price copied: ${CurrencyHelper.formatAmount(qtnItem.unitPrice, qtn.currency)}'),
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
                                if (poNumbers.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.description, size: 16, color: Colors.green[700]),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Wrap(
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

  Future<void> _saveQuotation() async {
    if (_inquiry == null) return;

    setState(() => _isSaving = true);

    try {
      final items = <QuotationItem>[];
      for (int i = 0; i < _inquiry!.items.length; i++) {
        final inquiryItem = _inquiry!.items[i];
        final priceText = _priceControllers[i]?.text ?? '0';
        final totalText = _totalControllers[i]?.text ?? '0';
        final quantityText = _quantityControllers[i]?.text ?? inquiryItem.quantity.toString();
        final materialCodeText = _materialCodeControllers[i]?.text ?? inquiryItem.itemCode;
        final unitPrice = double.tryParse(priceText) ?? 0.0;
        final total = double.tryParse(totalText) ?? 0.0;
        final quantity = double.tryParse(quantityText) ?? inquiryItem.quantity;

        // Set status to pending if price is missing or zero
        final isPriced = unitPrice > 0;
        final status = isPriced ? 'ready' : 'pending';
        
        items.add(QuotationItem(
          itemName: inquiryItem.itemName,
          itemCode: materialCodeText?.isNotEmpty == true ? materialCodeText : inquiryItem.itemCode,
          description: inquiryItem.description,
          quantity: quantity,
          unit: inquiryItem.unit,
          unitPrice: unitPrice,
          total: total,
          manufacturerPart: inquiryItem.manufacturerPart,
          isPriced: isPriced,
          status: status,
        ));
      }

      // Check if all items were matched for status
      final allMatched = items.every((item) => item.unitPrice > 0);
      final quotationStatus = allMatched ? 'Quote Ready' : 'draft';
      
      // Generate quotation number using new format
      final quotationNumber = await _quotationNumberService.generateNextQuotationNumber();
      
      final quotation = Quotation(
        quotationNumber: quotationNumber,
        quotationDate: DateTime.now(),
        validityDate: _validityDate,
        customerName: _inquiry!.customerName,
        customerAddress: _inquiry!.customerAddress,
        customerEmail: _recipientEmailController.text.trim().isNotEmpty 
            ? _recipientEmailController.text.trim() 
            : _inquiry!.senderEmail,
        customerPhone: _inquiry!.customerPhone,
        items: items,
        totalAmount: _calculateGrandTotal(), // Includes 5% VAT
        currency: _currency,
        terms: _terms,
        notes: _notes,
        inquiryId: _inquiry!.id,
        status: quotationStatus,
        createdAt: DateTime.now(),
      );

      final savedQuotation = await ref.read(quotationProvider.notifier).addQuotation(quotation);

      // Update inquiry status
      if (_inquiry!.id != null) {
        await ref.read(inquiryProvider.notifier).updateInquiry(
          _inquiry!.copyWith(
            status: 'quoted',
            quotationId: savedQuotation?.id,
          ),
        );
      }

      // Auto-send email if enabled and recipient email is available
      // Use senderEmail from inquiry (the email address that sent the inquiry)
      bool emailSent = false;
      // Get sender email from the "Send To:" field (which should be populated with senderEmail)
      final recipientEmail = _recipientEmailController.text.trim();
      debugPrint('📧 Preparing to send quotation email to: $recipientEmail');
      
      if (_autoSendEmail && recipientEmail.isNotEmpty && savedQuotation != null) {
        try {
          // Check if there are pending items
          final hasPendingItems = savedQuotation.items.any((item) => item.status == 'pending');
          
          // Generate quotation PDF file - use partial PDF if there are pending items
          final pdfBytes = hasPendingItems
              ? await _pdfService.generatePartialQuotePDF(savedQuotation)
              : await _pdfService.generateQuotationPDF(savedQuotation);
          
          // Prepare items data for email body - only include ready items
          final readyItems = savedQuotation.items.where((item) => item.status == 'ready').toList();
          final itemsData = readyItems.map((item) => {
            'itemName': item.itemName,
            'quantity': item.quantity,
            'unit': item.unit,
            'unitPrice': item.unitPrice,
            'total': item.total,
          }).toList();
          
          // Prepare pending items data for email body
          final pendingItemsList = savedQuotation.items.where((item) => item.status == 'pending' || item.unitPrice == 0).toList();
          final pendingItemsData = pendingItemsList.map((item) => {
            'itemName': item.itemName,
            'itemCode': item.itemCode ?? 'N/A',
          }).toList();
          
          // Calculate grand total from ready items only
          final readySubtotal = readyItems.fold<double>(0.0, (sum, item) => sum + item.total);
          final readyVat = readySubtotal * 0.05;
          final readyGrandTotal = readySubtotal + readyVat;
          
          // Send email using Gmail API with reply thread support
          emailSent = await _emailService.sendQuotationEmail(
            to: recipientEmail,
            quotationNumber: savedQuotation.quotationNumber,
            quotationPdf: pdfBytes,
            customerName: savedQuotation.customerName,
            items: itemsData,
            grandTotal: hasPendingItems ? readyGrandTotal : savedQuotation.totalAmount,
            currency: savedQuotation.currency,
            cc: _ccRecipients.isNotEmpty ? _ccRecipients : null,
            threadId: _emailThreadId,
            originalSubject: _originalEmailSubject,
            pendingItems: hasPendingItems ? pendingItemsData : null, // Pass pending items for email body
          );

          if (emailSent) {
            // Update quotation status to 'sent'
            if (savedQuotation.id != null) {
              await ref.read(quotationProvider.notifier).updateQuotation(
                savedQuotation.copyWith(status: 'sent'),
              );
            }
            
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
                SnackBar(
                  content: Text('Quotation created but email sending failed'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 5),
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
                content: Text('Quotation created but email failed: $e'),
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
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                const Text('Quotation created successfully'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Redirect to home/dashboard after successful quotation generation
      if (mounted) {
        // Small delay to show success message
        await Future.delayed(const Duration(milliseconds: 500));
        context.go('/dashboard');
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Create Quotation')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_inquiry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Create Quotation')),
        body: const Center(child: Text('Inquiry not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Quotation'),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveQuotation,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderCard(context),
            const SizedBox(height: 16),
            _buildCustomerCard(context),
            const SizedBox(height: 16),
            _buildItemsCard(context),
            const SizedBox(height: 16),
            _buildTermsCard(context),
            const SizedBox(height: 16),
            _buildSummaryCard(context),
            const SizedBox(height: 16),
            _buildEmailOptionsCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailOptionsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Email Options',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            // Send To: Email Field
            TextField(
              controller: _recipientEmailController,
              decoration: InputDecoration(
                labelText: 'Send To:',
                hintText: 'Enter recipient email address',
                prefixIcon: const Icon(Icons.email),
                border: const OutlineInputBorder(),
                helperText: 'Email address extracted from inquiry. You can edit if needed.',
                suffixIcon: _recipientEmailController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _recipientEmailController.clear();
                          });
                        },
                      )
                    : null,
              ),
              keyboardType: TextInputType.emailAddress,
              onChanged: (value) {
                setState(() {
                  // Update state when email changes
                });
              },
            ),
            // CC Recipients section
            if (_ccRecipients.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'CC Recipients:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _ccRecipients.map((email) {
                  return Chip(
                    label: Text(email),
                    onDeleted: () {
                      setState(() {
                        _ccRecipients.remove(email);
                      });
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Automatically send quotation via email'),
              subtitle: _recipientEmailController.text.isNotEmpty
                  ? Text('Will send to: ${_recipientEmailController.text}')
                  : const Text('Recipient email not set'),
              value: _autoSendEmail && _recipientEmailController.text.isNotEmpty,
              onChanged: _recipientEmailController.text.isNotEmpty
                  ? (value) {
                      setState(() {
                        _autoSendEmail = value;
                      });
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quotation Details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _currency,
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      border: OutlineInputBorder(),
                    ),
                    items: ['AED', 'USD', 'INR', 'EUR', 'GBP']
                        .map((currency) => DropdownMenuItem(
                              value: currency,
                              child: Text(currency),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _currency = value ?? 'AED';
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _validityDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setState(() {
                          _validityDate = date;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Validity Date',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(DateFormat('MMM dd, yyyy').format(_validityDate)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer Information',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(_inquiry!.customerName),
            if (_inquiry!.customerAddress != null) ...[
              const SizedBox(height: 8),
              Text(_inquiry!.customerAddress!),
            ],
            if (_inquiry!.senderEmail != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.email, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    _inquiry!.senderEmail!,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildItemsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Items',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ...List.generate(_inquiry!.items.length, (index) {
              final item = _inquiry!.items[index];
              return _buildItemRow(context, item, index);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(BuildContext context, item, int index) {
    // Debug: Log when building item row
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('🔨 [Build] Built item row for index: $index');
      print('FocusNode[$index] exists: ${_priceFocusNodes[index] != null}');
      print('PriceController[$index] exists: ${_priceControllers[index] != null}');
    });
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.itemName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          // Material Code field
          TextField(
            controller: _materialCodeControllers[index],
            decoration: InputDecoration(
              labelText: 'Material Code',
              border: const OutlineInputBorder(),
              hintText: item.itemCode ?? 'Enter material code',
              suffixIcon: IconButton(
                icon: const Icon(Icons.history),
                onPressed: () {
                  print('🔘 [Material Code History Icon] Button pressed for index: $index');
                  _showHistoricalDataDialog(index);
                },
                tooltip: 'View price history',
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantityControllers[index],
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    border: const OutlineInputBorder(),
                    suffixText: item.unit,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _calculateTotal(index),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _priceControllers[index],
                  focusNode: _priceFocusNodes[index],
                  decoration: InputDecoration(
                    labelText: 'Unit Price (Amount)',
                    border: const OutlineInputBorder(),
                    prefixText: CurrencyHelper.getCurrencySymbol(_currency),
                  ),
                  keyboardType: TextInputType.number,
                  onTap: () {
                    print('========================================');
                    print('👆👆👆 [TextFormField onTap] Tapped for index: $index');
                    print('FocusNode exists: ${_priceFocusNodes[index] != null}');
                    print('Controller exists: ${_priceControllers[index] != null}');
                    print('Timestamp: ${DateTime.now()}');
                    print('========================================');
                    debugPrint('👆👆👆 [TextFormField onTap] Tapped for index: $index');
                    // Immediately show dialog on tap
                    _showHistoricalDataDialog(index);
                  },
                  onChanged: (_) => _calculateTotal(index),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _totalControllers[index],
                  decoration: InputDecoration(
                    labelText: 'Total',
                    border: const OutlineInputBorder(),
                    prefixText: CurrencyHelper.getCurrencySymbol(_currency),
                  ),
                  keyboardType: TextInputType.number,
                  readOnly: true,
                ),
              ),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _buildTermsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Terms & Notes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Terms & Conditions',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              onChanged: (value) => _terms = value,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              onChanged: (value) => _notes = value,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Summary',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Subtotal',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  CurrencyHelper.formatAmount(_calculateSubtotal(), _currency),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'VAT (5%)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  CurrencyHelper.formatAmount(_calculateVAT(), _currency),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Grand Total',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  CurrencyHelper.formatAmount(_calculateGrandTotal(), _currency),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            if (_allItemsMatched) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'All items matched - Quote Ready',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

