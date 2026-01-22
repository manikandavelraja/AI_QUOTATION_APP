import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/delivery_provider.dart';
import '../providers/supplier_order_provider.dart';
import '../providers/po_provider.dart';
import '../../domain/entities/delivery_document.dart';
import '../../domain/entities/supplier_order.dart';
import '../../domain/entities/purchase_order.dart';
import '../../core/utils/currency_helper.dart';

class DeliveryDocumentCreateScreen extends ConsumerStatefulWidget {
  final String? supplierOrderId; // Optional: if creating from supplier order
  final String? poId; // Optional: if creating from PO directly

  const DeliveryDocumentCreateScreen({super.key, this.supplierOrderId, this.poId});

  @override
  ConsumerState<DeliveryDocumentCreateScreen> createState() => _DeliveryDocumentCreateScreenState();
}

class _DeliveryDocumentCreateScreenState extends ConsumerState<DeliveryDocumentCreateScreen> {
  SupplierOrder? _supplierOrder;
  PurchaseOrder? _po;
  bool _isLoading = true;
  bool _isSaving = false;
  
  final _customerNameController = TextEditingController();
  final _customerAddressController = TextEditingController();
  final _customerEmailController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerTRNController = TextEditingController();
  
  String _documentType = 'commercial_invoice';
  String _currency = 'AED';
  String? _terms;
  String? _notes;
  DateTime _documentDate = DateTime.now();
  double? _vatRate;
  
  List<DeliveryItem> _items = [];

  @override
  void initState() {
    super.initState();
    if (widget.supplierOrderId != null) {
      _loadSupplierOrder();
    } else if (widget.poId != null) {
      _loadPO();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerAddressController.dispose();
    _customerEmailController.dispose();
    _customerPhoneController.dispose();
    _customerTRNController.dispose();
    super.dispose();
  }

  Future<void> _loadSupplierOrder() async {
    setState(() => _isLoading = true);
    final order = await ref.read(supplierOrderProvider.notifier).getSupplierOrderById(widget.supplierOrderId!);
    setState(() {
      _supplierOrder = order;
      if (order != null) {
        _currency = order.currency ?? 'AED';
        _items = order.items.map((item) {
          return DeliveryItem(
            itemName: item.itemName,
            itemCode: item.itemCode,
            description: item.description,
            quantity: item.quantity,
            unit: item.unit,
            unitPrice: item.unitPrice,
            total: item.total,
          );
        }).toList();
        
        // Load PO if available
        if (order.poId != null) {
          _loadPOFromId(order.poId!);
        }
      }
      _isLoading = false;
    });
  }

  Future<void> _loadPOFromId(String poId) async {
    final po = await ref.read(poProvider.notifier).getPurchaseOrderById(poId);
    setState(() {
      _po = po;
      if (po != null) {
        _customerNameController.text = po.customerName;
        _customerAddressController.text = po.customerAddress ?? '';
        _customerEmailController.text = po.customerEmail ?? '';
      }
    });
  }

  Future<void> _loadPO() async {
    setState(() => _isLoading = true);
    final po = await ref.read(poProvider.notifier).getPurchaseOrderById(widget.poId!);
    setState(() {
      _po = po;
      if (po != null) {
        _currency = po.currency ?? 'AED';
        _customerNameController.text = po.customerName;
        _customerAddressController.text = po.customerAddress ?? '';
        _customerEmailController.text = po.customerEmail ?? '';
        _items = po.lineItems.map((item) {
          return DeliveryItem(
            itemName: item.itemName,
            itemCode: item.itemCode,
            description: item.description,
            quantity: item.quantity,
            unit: item.unit,
            unitPrice: item.unitPrice,
            total: item.total,
          );
        }).toList();
      }
      _isLoading = false;
    });
  }

  double _calculateSubtotal() {
    return _items.fold(0.0, (sum, item) => sum + item.total);
  }

  double _calculateVAT() {
    if (_vatRate == null || _vatRate == 0) return 0.0;
    return _calculateSubtotal() * (_vatRate! / 100);
  }

  double _calculateTotal() {
    return _calculateSubtotal() + _calculateVAT();
  }

  Future<void> _saveDocument() async {
    if (_customerNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter customer name')),
      );
      return;
    }

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final document = DeliveryDocument(
        documentNumber: 'DOC-${DateTime.now().millisecondsSinceEpoch}',
        documentType: _documentType,
        documentDate: _documentDate,
        customerName: _customerNameController.text,
        customerAddress: _customerAddressController.text.isEmpty ? null : _customerAddressController.text,
        customerEmail: _customerEmailController.text.isEmpty ? null : _customerEmailController.text,
        customerPhone: _customerPhoneController.text.isEmpty ? null : _customerPhoneController.text,
        customerTRN: _customerTRNController.text.isEmpty ? null : _customerTRNController.text,
        items: _items,
        subtotal: _calculateSubtotal(),
        vatAmount: _vatRate != null && _vatRate! > 0 ? _calculateVAT() : null,
        totalAmount: _calculateTotal(),
        currency: _currency,
        terms: _terms,
        notes: _notes,
        status: 'draft',
        createdAt: DateTime.now(),
        poId: widget.poId ?? _po?.id,
        supplierOrderId: widget.supplierOrderId ?? _supplierOrder?.id,
      );

      final savedDoc = await ref.read(deliveryProvider.notifier).addDeliveryDocument(document);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery document created successfully'),
            backgroundColor: Colors.green,
          ),
        );
        if (savedDoc?.id != null) {
          context.go('/delivery-document-detail/${savedDoc!.id}');
        } else {
          context.pop();
        }
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
        appBar: AppBar(title: const Text('Create Delivery Document')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Delivery Document'),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveDocument,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.supplierOrderId != null && _supplierOrder != null) ...[
              _buildSupplierOrderCard(context),
              const SizedBox(height: 16),
            ],
            if (widget.poId != null && _po != null) ...[
              _buildPOCard(context),
              const SizedBox(height: 16),
            ],
            _buildDocumentTypeCard(context),
            const SizedBox(height: 16),
            _buildCustomerCard(context),
            const SizedBox(height: 16),
            _buildItemsCard(context),
            const SizedBox(height: 16),
            _buildTermsCard(context),
            const SizedBox(height: 16),
            _buildSummaryCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSupplierOrderCard(BuildContext context) {
    if (_supplierOrder == null) return const SizedBox.shrink();
    
    return Card(
      color: Colors.purple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_cart, color: Colors.purple),
                const SizedBox(width: 8),
                Text(
                  'Supplier Order: ${_supplierOrder!.orderNumber}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Supplier: ${_supplierOrder!.supplierName}'),
            Text('Total: ${CurrencyHelper.formatAmount(_supplierOrder!.totalAmount, _supplierOrder!.currency)}'),
          ],
        ),
      ),
    );
  }

  Widget _buildPOCard(BuildContext context) {
    if (_po == null) return const SizedBox.shrink();
    
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Customer PO: ${_po!.poNumber}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Customer: ${_po!.customerName}'),
            Text('Total: ${CurrencyHelper.formatAmount(_po!.totalAmount, _po!.currency)}'),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentTypeCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Document Type',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _documentType,
              decoration: const InputDecoration(
                labelText: 'Document Type',
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'commercial_invoice',
                  child: Row(
                    children: [
                      const Icon(Icons.receipt, size: 20),
                      const SizedBox(width: 8),
                      const Text('Commercial Invoice'),
                    ],
                  ),
                ),
                DropdownMenuItem(
                  value: 'delivery_order',
                  child: Row(
                    children: [
                      const Icon(Icons.local_shipping, size: 20),
                      const SizedBox(width: 8),
                      const Text('Delivery Order'),
                    ],
                  ),
                ),
                DropdownMenuItem(
                  value: 'both',
                  child: Row(
                    children: [
                      const Icon(Icons.description, size: 20),
                      const SizedBox(width: 8),
                      const Text('Both'),
                    ],
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _documentType = value ?? 'commercial_invoice';
                });
              },
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _documentDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) {
                  setState(() => _documentDate = date);
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Document Date',
                  border: OutlineInputBorder(),
                ),
                child: Text(DateFormat('MMM dd, yyyy').format(_documentDate)),
              ),
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
            TextField(
              controller: _customerNameController,
              decoration: const InputDecoration(
                labelText: 'Customer Name *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customerAddressController,
              decoration: const InputDecoration(
                labelText: 'Address',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customerEmailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _customerPhoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customerTRNController,
              decoration: const InputDecoration(
                labelText: 'Tax Registration Number (TRN)',
                border: OutlineInputBorder(),
              ),
            ),
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
              'Items (${_items.length})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_items.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('No items available'),
                ),
              )
            else
              ..._items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.itemName,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if (item.description != null)
                                Text(
                                  item.description!,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              Text(
                                '${item.quantity} ${item.unit} × ${CurrencyHelper.getCurrencySymbol(_currency)}${item.unitPrice.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          CurrencyHelper.formatAmount(item.total, _currency),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
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
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'VAT Rate (%)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      setState(() {
                        _vatRate = double.tryParse(value);
                      });
                    },
                  ),
                ),
              ],
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
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  CurrencyHelper.formatAmount(_calculateSubtotal(), _currency),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            if (_vatRate != null && _vatRate! > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'VAT (${_vatRate!.toStringAsFixed(1)}%)',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    CurrencyHelper.formatAmount(_calculateVAT(), _currency),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ],
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Amount',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  CurrencyHelper.formatAmount(_calculateTotal(), _currency),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

