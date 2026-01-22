import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/delivery_provider.dart';
import '../../domain/entities/delivery_document.dart';
import '../../core/utils/currency_helper.dart';

class DeliveryDocumentDetailScreen extends ConsumerStatefulWidget {
  final String documentId;

  const DeliveryDocumentDetailScreen({super.key, required this.documentId});

  @override
  ConsumerState<DeliveryDocumentDetailScreen> createState() => _DeliveryDocumentDetailScreenState();
}

class _DeliveryDocumentDetailScreenState extends ConsumerState<DeliveryDocumentDetailScreen> {
  DeliveryDocument? _document;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    setState(() => _isLoading = true);
    final doc = await ref.read(deliveryProvider.notifier).getDeliveryDocumentById(widget.documentId);
    setState(() {
      _document = doc;
      _isLoading = false;
    });
  }

  Future<void> _deleteDocument() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this delivery document?'),
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

    if (confirmed == true && _document?.id != null) {
      await ref.read(deliveryProvider.notifier).deleteDeliveryDocument(_document!.id!);
      if (mounted) {
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Delivery Document Detail')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_document == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Delivery Document Detail')),
        body: const Center(child: Text('Document not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_document!.documentNumber),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteDocument,
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
    String docTypeText;
    IconData docIcon;
    
    switch (_document!.documentType) {
      case 'commercial_invoice':
        docTypeText = 'Commercial Invoice';
        docIcon = Icons.receipt;
        break;
      case 'delivery_order':
        docTypeText = 'Delivery Order';
        docIcon = Icons.local_shipping;
        break;
      case 'both':
        docTypeText = 'Commercial Invoice & Delivery Order';
        docIcon = Icons.description;
        break;
      default:
        docTypeText = _document!.documentType;
        docIcon = Icons.description;
    }
    
    switch (_document!.status) {
      case 'draft':
        statusColor = Colors.orange;
        break;
      case 'generated':
        statusColor = Colors.blue;
        break;
      case 'sent':
        statusColor = Colors.green;
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
                Row(
                  children: [
                    Icon(docIcon, color: statusColor),
                    const SizedBox(width: 8),
                    Text(
                      docTypeText,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                Chip(
                  label: Text(_document!.status.toUpperCase()),
                  backgroundColor: statusColor.withOpacity(0.2),
                  labelStyle: TextStyle(color: statusColor),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(context, 'Document Number', _document!.documentNumber),
            _buildInfoRow(context, 'Document Date', DateFormat('MMM dd, yyyy').format(_document!.documentDate)),
            if (_document!.poId != null)
              _buildInfoRow(context, 'Customer PO ID', _document!.poId!),
            if (_document!.supplierOrderId != null)
              _buildInfoRow(context, 'Supplier Order ID', _document!.supplierOrderId!),
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
            Text(
              _document!.customerName,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (_document!.customerAddress != null) ...[
              const SizedBox(height: 8),
              Text(
                _document!.customerAddress!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_document!.customerEmail != null) ...[
              const SizedBox(height: 8),
              Text(
                _document!.customerEmail!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_document!.customerPhone != null) ...[
              const SizedBox(height: 8),
              Text(
                _document!.customerPhone!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_document!.customerTRN != null) ...[
              const SizedBox(height: 8),
              Text(
                'TRN: ${_document!.customerTRN}',
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
            ..._document!.items.map((item) => _buildLineItemRow(context, item)),
          ],
        ),
      ),
    );
  }

  Widget _buildLineItemRow(BuildContext context, item) {
    final currencyCode = _document!.currency;
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
                  'Subtotal',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  CurrencyHelper.formatAmount(_document!.subtotal, _document!.currency),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            if (_document!.vatAmount != null && _document!.vatAmount! > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'VAT',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    CurrencyHelper.formatAmount(_document!.vatAmount!, _document!.currency),
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
                  CurrencyHelper.formatAmount(_document!.totalAmount, _document!.currency),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            if (_document!.terms != null) ...[
              const SizedBox(height: 12),
              Text(
                'Terms',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(_document!.terms!),
            ],
            if (_document!.notes != null) ...[
              const SizedBox(height: 12),
              Text(
                'Notes',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(_document!.notes!),
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

