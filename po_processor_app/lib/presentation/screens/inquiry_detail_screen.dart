import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/inquiry_provider.dart';
import '../../domain/entities/customer_inquiry.dart';

class InquiryDetailScreen extends ConsumerStatefulWidget {
  final String inquiryId;

  const InquiryDetailScreen({super.key, required this.inquiryId});

  @override
  ConsumerState<InquiryDetailScreen> createState() => _InquiryDetailScreenState();
}

class _InquiryDetailScreenState extends ConsumerState<InquiryDetailScreen> {
  CustomerInquiry? _inquiry;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInquiry();
  }

  Future<void> _loadInquiry() async {
    setState(() => _isLoading = true);
    final inquiry = await ref.read(inquiryProvider.notifier).getInquiryById(widget.inquiryId);
    setState(() {
      _inquiry = inquiry;
      _isLoading = false;
    });
  }

  Future<void> _deleteInquiry() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this inquiry?'),
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

    if (confirmed == true && _inquiry?.id != null) {
      await ref.read(inquiryProvider.notifier).deleteInquiry(_inquiry!.id!);
      if (mounted) {
        context.pop();
      }
    }
  }

  Future<void> _createQuotation() async {
    if (_inquiry == null) return;
    
    // Navigate to create quotation screen with inquiry data
    if (mounted) {
      context.push('/create-quotation/${_inquiry!.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Inquiry Detail')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_inquiry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Inquiry Detail')),
        body: const Center(
          child: Text('Inquiry not found'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_inquiry!.inquiryNumber),
        actions: [
          if (_inquiry!.items.any((i) => i.status == 'pending') ||
              _inquiry!.status == 'pending' || _inquiry!.status == 'reviewed')
            IconButton(
              icon: const Icon(Icons.create),
              onPressed: _createQuotation,
              tooltip: 'Create / Update Quotation',
            ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteInquiry,
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
            if (_inquiry!.notes != null) ...[
              const SizedBox(height: 16),
              _buildNotesCard(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    Color statusColor;
    String statusText;
    switch (_inquiry!.status) {
      case 'pending':
        statusColor = Colors.orange;
        statusText = 'Pending';
        break;
      case 'reviewed':
        statusColor = Colors.blue;
        statusText = 'Reviewed';
        break;
      case 'quoted':
        statusColor = Colors.green;
        statusText = 'Quoted';
        break;
      case 'partially_quoted':
        statusColor = Colors.teal;
        statusText = 'Partially Quoted';
        break;
      case 'converted_to_po':
        statusColor = Colors.purple;
        statusText = 'Converted to PO';
        break;
      default:
        statusColor = Colors.grey;
        statusText = _inquiry!.status;
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
                  'Inquiry Number',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Chip(
                  label: Text(statusText),
                  backgroundColor: statusColor.withOpacity(0.2),
                  labelStyle: TextStyle(color: statusColor),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(context, 'Inquiry Date', DateFormat('MMM dd, yyyy').format(_inquiry!.inquiryDate)),
            if (_inquiry!.quotationId != null)
              _buildInfoRow(context, 'Quotation ID', _inquiry!.quotationId!),
            if (_inquiry!.poId != null)
              _buildInfoRow(context, 'PO ID', _inquiry!.poId!),
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
              _inquiry!.customerName,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (_inquiry!.customerAddress != null) ...[
              const SizedBox(height: 8),
              Text(
                _inquiry!.customerAddress!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_inquiry!.customerEmail != null) ...[
              const SizedBox(height: 8),
              Text(
                _inquiry!.customerEmail!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_inquiry!.customerPhone != null) ...[
              const SizedBox(height: 8),
              Text(
                _inquiry!.customerPhone!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_inquiry!.senderEmail != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.email, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Recipient Email',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.email_outlined, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _inquiry!.senderEmail!,
                        style: TextStyle(
                          color: Colors.blue.shade900,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
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

  Widget _buildItemsCard(BuildContext context) {
    final quotedCount = _inquiry!.items.where((i) => i.status == 'quoted').length;
    final pendingCount = _inquiry!.items.length - quotedCount;
    final summary = _inquiry!.items.isEmpty
        ? 'Items (0)'
        : (quotedCount > 0 && pendingCount > 0)
            ? 'Items (${_inquiry!.items.length}) — $quotedCount quoted, $pendingCount pending'
            : 'Items (${_inquiry!.items.length})';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ..._inquiry!.items.map((item) => _buildItemRow(context, item)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(BuildContext context, InquiryItem item) {
    final isQuoted = item.status == 'quoted';
    final itemStatusColor = isQuoted ? Colors.green : Colors.orange;
    final itemStatusText = isQuoted ? 'Quoted' : 'Pending';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.itemName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Chip(
                label: Text(
                  itemStatusText,
                  style: const TextStyle(fontSize: 10),
                ),
                backgroundColor: itemStatusColor.withOpacity(0.2),
                labelStyle: TextStyle(color: itemStatusColor),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          if (item.itemCode != null)
            Text(
              'Code: ${item.itemCode}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (item.description != null)
            Text(
              item.description!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Text(
            'Quantity: ${item.quantity} ${item.unit}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (item.manufacturerPart != null)
            Text(
              'Manufacturer Part: ${item.manufacturerPart}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _buildNotesCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(_inquiry!.notes!),
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

