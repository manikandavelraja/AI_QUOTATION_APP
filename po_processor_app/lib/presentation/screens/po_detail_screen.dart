import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/po_provider.dart';
import '../../domain/entities/purchase_order.dart';
import '../../core/utils/currency_helper.dart';

class PODetailScreen extends ConsumerStatefulWidget {
  final String poId;

  const PODetailScreen({super.key, required this.poId});

  @override
  ConsumerState<PODetailScreen> createState() => _PODetailScreenState();
}

class _PODetailScreenState extends ConsumerState<PODetailScreen> {
  PurchaseOrder? _po;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPO();
  }

  Future<void> _loadPO() async {
    setState(() => _isLoading = true);
    final po = await ref.read(poProvider.notifier).getPurchaseOrderById(widget.poId);
    setState(() {
      _po = po;
      _isLoading = false;
    });
  }

  Future<void> _deletePO() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('confirm_delete'.tr()),
        content: Text('confirm_delete_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('no'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('yes'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true && _po != null) {
      await ref.read(poProvider.notifier).deletePurchaseOrder(_po!.id!);
      if (mounted) {
        context.pop();
      }
    }
  }

  Future<void> _createSupplierOrder() async {
    if (_po == null || _po!.id == null) return;
    
    if (mounted) {
      context.push('/supplier-order-create?poId=${_po!.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('po_detail'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_po == null) {
      return Scaffold(
        appBar: AppBar(title: Text('po_detail'.tr())),
        body: Center(
          child: Text('po_not_found'.tr()),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_po!.poNumber),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: _createSupplierOrder,
            tooltip: 'Create Supplier Order',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deletePO,
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
    switch (_po!.status) {
      case 'expired':
        statusColor = Colors.red;
        break;
      case 'expiring_soon':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = Colors.green;
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
                  'po_number'.tr(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Chip(
                  label: Text(_po!.status.tr()),
                  backgroundColor: statusColor.withOpacity(0.2),
                  labelStyle: TextStyle(color: statusColor),
                ),
              ],
            ),
            const SizedBox(height: 12),
              _buildInfoRow(context, 'quotation_number'.tr(), _po?.quotationReference?? ''),
            _buildInfoRow(context, 'po_date'.tr(), DateFormat('MMM dd, yyyy').format(_po!.poDate)),
            _buildInfoRow(context, 'expiry_date'.tr(), DateFormat('MMM dd, yyyy').format(_po!.expiryDate)),
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
              'customer_name'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              _po!.customerName,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (_po!.customerAddress != null) ...[
              const SizedBox(height: 8),
              Text(
                _po!.customerAddress!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_po!.customerEmail != null) ...[
              const SizedBox(height: 8),
              Text(
                _po!.customerEmail!,
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
              'line_items'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ..._po!.lineItems.map((item) => _buildLineItemRow(context, item)),
          ],
        ),
      ),
    );
  }

  Widget _buildLineItemRow(BuildContext context, item) {
    // Use the PO's currency for all line items
    final currencyCode = _po!.currency;
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
              'summary'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'total_amount'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  CurrencyHelper.formatAmount(_po!.totalAmount, _po!.currency),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            if (_po!.terms != null) ...[
              const SizedBox(height: 12),
              Text(
                'terms'.tr(),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(_po!.terms!),
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

