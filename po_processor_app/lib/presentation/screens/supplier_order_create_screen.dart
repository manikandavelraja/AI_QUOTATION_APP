import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/supplier_order_provider.dart';
import '../providers/po_provider.dart';
import '../../domain/entities/supplier_order.dart';
import '../../domain/entities/purchase_order.dart';
import '../../core/utils/currency_helper.dart';

class SupplierOrderCreateScreen extends ConsumerStatefulWidget {
  final String? poId; // Optional: if creating from PO

  const SupplierOrderCreateScreen({super.key, this.poId});

  @override
  ConsumerState<SupplierOrderCreateScreen> createState() => _SupplierOrderCreateScreenState();
}

class _SupplierOrderCreateScreenState extends ConsumerState<SupplierOrderCreateScreen> {
  PurchaseOrder? _po;
  bool _isLoading = true;
  bool _isSaving = false;
  
  final _supplierNameController = TextEditingController();
  final _supplierAddressController = TextEditingController();
  final _supplierEmailController = TextEditingController();
  final _supplierPhoneController = TextEditingController();
  final Map<int, TextEditingController> _priceControllers = {};
  final Map<int, TextEditingController> _quantityControllers = {};
  
  String _currency = 'AED';
  String? _terms;
  String? _notes;
  DateTime _orderDate = DateTime.now();
  DateTime? _expectedDeliveryDate;
  
  List<SupplierOrderItem> _items = [];

  @override
  void initState() {
    super.initState();
    if (widget.poId != null) {
      _loadPO();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _supplierNameController.dispose();
    _supplierAddressController.dispose();
    _supplierEmailController.dispose();
    _supplierPhoneController.dispose();
    for (var controller in _priceControllers.values) {
      controller.dispose();
    }
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPO() async {
    setState(() => _isLoading = true);
    final po = await ref.read(poProvider.notifier).getPurchaseOrderById(widget.poId!);
    setState(() {
      _po = po;
      if (po != null) {
        _currency = po.currency ?? 'AED';
        _items = po.lineItems.map((item) {
          final priceController = TextEditingController(text: item.unitPrice.toStringAsFixed(2));
          final qtyController = TextEditingController(text: item.quantity.toStringAsFixed(2));
          _priceControllers[_items.length] = priceController;
          _quantityControllers[_items.length] = qtyController;
          
          return SupplierOrderItem(
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

  void _addItem() {
    setState(() {
      final index = _items.length;
      _priceControllers[index] = TextEditingController();
      _quantityControllers[index] = TextEditingController(text: '1');
      _items.add(SupplierOrderItem(
        itemName: '',
        quantity: 1.0,
        unit: 'pcs',
        unitPrice: 0.0,
        total: 0.0,
      ));
    });
  }

  void _removeItem(int index) {
    setState(() {
      _priceControllers[index]?.dispose();
      _quantityControllers[index]?.dispose();
      _priceControllers.remove(index);
      _quantityControllers.remove(index);
      _items.removeAt(index);
      
      // Reindex controllers
      final newPriceControllers = <int, TextEditingController>{};
      final newQuantityControllers = <int, TextEditingController>{};
      for (int i = 0; i < _items.length; i++) {
        if (_priceControllers.containsKey(i)) {
          newPriceControllers[i] = _priceControllers[i]!;
        }
        if (_quantityControllers.containsKey(i)) {
          newQuantityControllers[i] = _quantityControllers[i]!;
        }
      }
      _priceControllers.clear();
      _quantityControllers.clear();
      _priceControllers.addAll(newPriceControllers);
      _quantityControllers.addAll(newQuantityControllers);
    });
  }

  void _updateItem(int index) {
    if (index >= _items.length) return;
    
    final priceText = _priceControllers[index]?.text ?? '0';
    final qtyText = _quantityControllers[index]?.text ?? '0';
    final price = double.tryParse(priceText) ?? 0.0;
    final qty = double.tryParse(qtyText) ?? 0.0;
    final total = price * qty;
    
    setState(() {
      _items[index] = SupplierOrderItem(
        itemName: _items[index].itemName,
        itemCode: _items[index].itemCode,
        description: _items[index].description,
        quantity: qty,
        unit: _items[index].unit,
        unitPrice: price,
        total: total,
      );
    });
  }

  double _calculateGrandTotal() {
    return _items.fold(0.0, (sum, item) => sum + item.total);
  }

  Future<void> _saveOrder() async {
    if (_supplierNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter supplier name')),
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
      final order = SupplierOrder(
        orderNumber: 'SO-${DateTime.now().millisecondsSinceEpoch}',
        orderDate: _orderDate,
        expectedDeliveryDate: _expectedDeliveryDate,
        supplierName: _supplierNameController.text,
        supplierAddress: _supplierAddressController.text.isEmpty ? null : _supplierAddressController.text,
        supplierEmail: _supplierEmailController.text.isEmpty ? null : _supplierEmailController.text,
        supplierPhone: _supplierPhoneController.text.isEmpty ? null : _supplierPhoneController.text,
        items: _items,
        totalAmount: _calculateGrandTotal(),
        currency: _currency,
        terms: _terms,
        notes: _notes,
        status: 'pending',
        createdAt: DateTime.now(),
        poId: widget.poId,
      );

      final savedOrder = await ref.read(supplierOrderProvider.notifier).addSupplierOrder(order);

      // Update PO status to awaiting_ordered if created from PO
      if (widget.poId != null && _po != null) {
        final updatedPO = _po!.copyWith(
          status: 'awaiting_ordered',
          updatedAt: DateTime.now(),
        );
        await ref.read(poProvider.notifier).updatePurchaseOrder(updatedPO);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Supplier order created successfully'),
            backgroundColor: Colors.green,
          ),
        );
        if (savedOrder?.id != null) {
          context.go('/supplier-order-detail/${savedOrder!.id}');
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
        appBar: AppBar(title: const Text('Create Supplier Order')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.poId != null ? 'Deliver Order' : 'Create Supplier Order'),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveOrder,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.poId != null && _po != null) ...[
              _buildPOCard(context),
              const SizedBox(height: 16),
            ],
            _buildSupplierCard(context),
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

  Widget _buildSupplierCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Supplier Information',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _supplierNameController,
              decoration: const InputDecoration(
                labelText: 'Supplier Name *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _supplierAddressController,
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
                    controller: _supplierEmailController,
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
                    controller: _supplierPhoneController,
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
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _orderDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setState(() => _orderDate = date);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Order Date',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(DateFormat('MMM dd, yyyy').format(_orderDate)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _expectedDeliveryDate ?? DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setState(() => _expectedDeliveryDate = date);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Expected Delivery Date',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(_expectedDeliveryDate != null
                          ? DateFormat('MMM dd, yyyy').format(_expectedDeliveryDate!)
                          : 'Not set'),
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

  Widget _buildItemsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Items',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addItem,
                  tooltip: 'Add Item',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_items.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('No items. Click + to add items.'),
                ),
              )
            else
              ...List.generate(_items.length, (index) {
                return _buildItemRow(context, index);
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(BuildContext context, int index) {
    final item = _items[index];
    final isFromPO = widget.poId != null && _po != null;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: isFromPO
                      ? Text(
                          item.itemName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        )
                      : TextField(
                          decoration: const InputDecoration(
                            labelText: 'Item Name',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _items[index] = item.copyWith(itemName: value);
                            });
                          },
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeItem(index),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityControllers[index],
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _updateItem(index),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _priceControllers[index],
                    decoration: InputDecoration(
                      labelText: 'Unit Price',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      prefixText: CurrencyHelper.getCurrencySymbol(_currency),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _updateItem(index),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Total',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      prefixText: CurrencyHelper.getCurrencySymbol(_currency),
                    ),
                    controller: TextEditingController(
                      text: item.total.toStringAsFixed(2),
                    ),
                    readOnly: true,
                  ),
                ),
              ],
            ),
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
          ],
        ),
      ),
    );
  }
}

