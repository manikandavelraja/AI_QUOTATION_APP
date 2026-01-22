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
  late TextEditingController _recipientEmailController;
  String _currency = 'AED';
  String? _terms;
  String? _notes;
  DateTime _validityDate = DateTime.now().add(const Duration(days: 30));
  final _emailService = EmailService();
  final _catalogService = CatalogService();
  final _pdfService = QuotationPDFService();
  bool _allItemsMatched = false;

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
    
    final item = _inquiry!.items[index];
    final priceText = _priceControllers[index]?.text ?? '0';
    final price = double.tryParse(priceText) ?? 0.0;
    final lineTotal = price * item.quantity; // Calculate line total
    
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

  Future<void> _saveQuotation() async {
    if (_inquiry == null) return;

    setState(() => _isSaving = true);

    try {
      final items = <QuotationItem>[];
      for (int i = 0; i < _inquiry!.items.length; i++) {
        final inquiryItem = _inquiry!.items[i];
        final priceText = _priceControllers[i]?.text ?? '0';
        final totalText = _totalControllers[i]?.text ?? '0';
        final unitPrice = double.tryParse(priceText) ?? 0.0;
        final total = double.tryParse(totalText) ?? 0.0;

        items.add(QuotationItem(
          itemName: inquiryItem.itemName,
          itemCode: inquiryItem.itemCode,
          description: inquiryItem.description,
          quantity: inquiryItem.quantity,
          unit: inquiryItem.unit,
          unitPrice: unitPrice,
          total: total,
          manufacturerPart: inquiryItem.manufacturerPart,
        ));
      }

      // Check if all items were matched for status
      final allMatched = items.every((item) => item.unitPrice > 0);
      final quotationStatus = allMatched ? 'Quote Ready' : 'draft';
      
      final quotation = Quotation(
        quotationNumber: 'QTN-${DateTime.now().millisecondsSinceEpoch}',
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
          // Generate quotation PDF file
          final pdfBytes = await _pdfService.generateQuotationPDF(savedQuotation);
          
          // Prepare items data for email body
          final itemsData = savedQuotation.items.map((item) => {
            'itemName': item.itemName,
            'quantity': item.quantity,
            'unit': item.unit,
            'unitPrice': item.unitPrice,
            'total': item.total,
          }).toList();
          
          // Send email using url_launcher (opens user's mail client)
          emailSent = await _emailService.sendQuotationEmail(
            to: recipientEmail,
            quotationNumber: savedQuotation.quotationNumber,
            quotationPdf: pdfBytes,
            customerName: savedQuotation.customerName,
            items: itemsData,
            grandTotal: savedQuotation.totalAmount,
            currency: savedQuotation.currency,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.itemName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (item.itemCode != null)
            Text(
              'Code: ${item.itemCode}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('Qty: ${item.quantity} ${item.unit}'),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _priceControllers[index],
                  decoration: InputDecoration(
                    labelText: 'Unit Price',
                    border: const OutlineInputBorder(),
                    prefixText: CurrencyHelper.getCurrencySymbol(_currency),
                  ),
                  keyboardType: TextInputType.number,
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

