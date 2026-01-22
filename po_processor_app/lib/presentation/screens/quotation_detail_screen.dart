import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/quotation_provider.dart';
import '../../domain/entities/quotation.dart';
import '../../core/utils/currency_helper.dart';

class QuotationDetailScreen extends ConsumerStatefulWidget {
  final String quotationId;

  const QuotationDetailScreen({super.key, required this.quotationId});

  @override
  ConsumerState<QuotationDetailScreen> createState() => _QuotationDetailScreenState();
}

class _QuotationDetailScreenState extends ConsumerState<QuotationDetailScreen> {
  Quotation? _quotation;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuotation();
  }

  Future<void> _loadQuotation() async {
    setState(() => _isLoading = true);
    final quotation = await ref.read(quotationProvider.notifier).getQuotationById(widget.quotationId);
    setState(() {
      _quotation = quotation;
      _isLoading = false;
    });
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
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'expired':
        return Colors.orange;
      case 'draft':
      default:
        return Colors.grey;
    }
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_quotation!.quotationNumber),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteQuotation,
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
            _buildSummaryCard(context),
            if (_quotation!.terms != null || _quotation!.notes != null) ...[
              const SizedBox(height: 16),
              _buildTermsCard(context),
            ],
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Quotation Details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Chip(
                  label: Text(_quotation!.status),
                  backgroundColor: _getStatusColor(_quotation!.status).withOpacity(0.2),
                  labelStyle: TextStyle(color: _getStatusColor(_quotation!.status)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(context, 'Quotation Number', _quotation!.quotationNumber),
            _buildInfoRow(context, 'Quotation Date', 
                '${_quotation!.quotationDate.day}/${_quotation!.quotationDate.month}/${_quotation!.quotationDate.year}'),
            _buildInfoRow(context, 'Valid Until', 
                '${_quotation!.validityDate.day}/${_quotation!.validityDate.month}/${_quotation!.validityDate.year}'),
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
              _quotation!.customerName,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (_quotation!.customerAddress != null) ...[
              const SizedBox(height: 8),
              Text(
                _quotation!.customerAddress!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_quotation!.customerEmail != null) ...[
              const SizedBox(height: 8),
              Text(
                _quotation!.customerEmail!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_quotation!.customerPhone != null) ...[
              const SizedBox(height: 8),
              Text(
                _quotation!.customerPhone!,
                style: Theme.of(context).textTheme.bodyMedium,
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
            ..._quotation!.items.map((item) => _buildItemRow(context, item)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(BuildContext context, item) {
    final currencyCode = _quotation!.currency ?? 'AED';
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
                if (item.itemCode != null)
                  Text(
                    'Code: ${item.itemCode}',
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
    final currencyCode = _quotation!.currency ?? 'AED';
    
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
                  CurrencyHelper.formatAmount(_quotation!.totalAmount, currencyCode),
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

  Widget _buildTermsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_quotation!.terms != null) ...[
              Text(
                'Terms & Conditions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(_quotation!.terms!),
              if (_quotation!.notes != null) const SizedBox(height: 16),
            ],
            if (_quotation!.notes != null) ...[
              Text(
                'Notes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(_quotation!.notes!),
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

