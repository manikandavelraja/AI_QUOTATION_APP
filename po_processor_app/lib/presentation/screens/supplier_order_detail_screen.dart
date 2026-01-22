import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/supplier_order_provider.dart';
import '../../domain/entities/supplier_order.dart';
import '../../core/utils/currency_helper.dart';

class SupplierOrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;

  const SupplierOrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<SupplierOrderDetailScreen> createState() => _SupplierOrderDetailScreenState();
}

class _SupplierOrderDetailScreenState extends ConsumerState<SupplierOrderDetailScreen> {
  SupplierOrder? _order;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    setState(() => _isLoading = true);
    final order = await ref.read(supplierOrderProvider.notifier).getSupplierOrderById(widget.orderId);
    setState(() {
      _order = order;
      _isLoading = false;
    });
  }

  Future<void> _deleteOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this supplier order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirmed == true && _order?.id != null) {
      await ref.read(supplierOrderProvider.notifier).deleteSupplierOrder(_order!.id!);
      if (mounted) {
        context.pop();
      }
    }
  }

  Future<void> _createDeliveryDocument() async {
    if (_order == null || _order!.id == null) return;
    
    if (mounted) {
      context.push('/delivery-document-create?supplierOrderId=${_order!.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Supplier Order Detail')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Supplier Order Detail')),
        body: const Center(child: Text('Order not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_order!.orderNumber),
        actions: [
          if (_order!.status == 'delivered' || _order!.status == 'confirmed')
            IconButton(
              icon: const Icon(Icons.receipt),
              onPressed: _createDeliveryDocument,
              tooltip: 'Create Delivery Document',
            ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteOrder,
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
            _buildSupplierCard(context),
            const SizedBox(height: 16),
            _buildLineItemsCard(context),
            const SizedBox(height: 16),
            _buildSummaryCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    Color statusColor;
    switch (_order!.status) {
      case 'pending':
        statusColor = Colors.orange;
        break;
      case 'confirmed':
        statusColor = Colors.blue;
        break;
      case 'in_transit':
        statusColor = Colors.purple;
        break;
      case 'delivered':
        statusColor = Colors.green;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

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
                  'Order Number',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Chip(
                  label: Text(_order!.status.replaceAll('_', ' ').toUpperCase()),
                  backgroundColor: statusColor.withOpacity(0.2),
                  labelStyle: TextStyle(color: statusColor),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(context, 'Order Date', DateFormat('MMM dd, yyyy').format(_order!.orderDate)),
            if (_order!.expectedDeliveryDate != null)
              _buildInfoRow(context, 'Expected Delivery', DateFormat('MMM dd, yyyy').format(_order!.expectedDeliveryDate!)),
            if (_order!.poId != null)
              _buildInfoRow(context, 'Customer PO ID', _order!.poId!),
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
            Text(
              _order!.supplierName,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (_order!.supplierAddress != null) ...[
              const SizedBox(height: 8),
              Text(
                _order!.supplierAddress!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_order!.supplierEmail != null) ...[
              const SizedBox(height: 8),
              Text(
                _order!.supplierEmail!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_order!.supplierPhone != null) ...[
              const SizedBox(height: 8),
              Text(
                _order!.supplierPhone!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLineItemsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Line Items',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ..._order!.items.map((item) => _buildLineItemRow(context, item)),
          ],
        ),
      ),
    );
  }

  Widget _buildLineItemRow(BuildContext context, item) {
    final currencyCode = _order!.currency;
    final currencySymbol = CurrencyHelper.getCurrencySymbol(currencyCode);
    
    return Padding(
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
                  '${item.quantity} ${item.unit} × $currencySymbol${item.unitPrice.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            CurrencyHelper.formatAmount(item.total, currencyCode),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
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
                  'Total Amount',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  CurrencyHelper.formatAmount(_order!.totalAmount, _order!.currency),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            if (_order!.terms != null) ...[
              const SizedBox(height: 12),
              Text(
                'Terms',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(_order!.terms!),
            ],
            if (_order!.notes != null) ...[
              const SizedBox(height: 12),
              Text(
                'Notes',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(_order!.notes!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

