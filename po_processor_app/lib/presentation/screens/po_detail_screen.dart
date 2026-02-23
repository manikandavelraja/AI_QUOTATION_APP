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
  bool _isUpdatingStatus = false;

  static const List<Map<String, String>> _statusOptions = [
    {'value': 'active', 'label': 'Active'},
    {'value': 'awaiting_ordered', 'label': 'Awaiting Ordered'},
    {'value': 'material_received', 'label': 'Material Received'},
    {'value': 'delivery_status', 'label': 'Delivered'},
  ];

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

  Future<void> _updatePOStatus(String newStatus) async {
    if (_po == null || _po!.id == null) return;
    setState(() => _isUpdatingStatus = true);
    try {
      final updated = _po!.copyWith(
        status: newStatus,
        updatedAt: DateTime.now(),
      );
      await ref.read(poProvider.notifier).updatePurchaseOrder(updated);
      if (mounted) {
        setState(() {
          _po = updated;
          _isUpdatingStatus = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to ${_statusOptions.firstWhere((e) => e['value'] == newStatus, orElse: () => {'label': newStatus})['label']}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('po_detail'.tr()),
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_po == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('po_detail'.tr()),
          elevation: 0,
        ),
        body: Center(
          child: Text('po_not_found'.tr()),
        ),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colorScheme.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _po!.poNumber,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: _deletePO,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Hero Header Section
            _buildHeroHeader(context, colorScheme),
            
            // Main Content
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // PO Information Card
                  _buildPOInfoCard(context, colorScheme),
                  const SizedBox(height: 20),
                  
                  // Customer & Vendor Section
                  _buildCustomerVendorSection(context, colorScheme),
                  const SizedBox(height: 20),
                  
                  // Line Items Card
                  _buildLineItemsCard(context, colorScheme),
                  const SizedBox(height: 20),
                  
                  // Summary Card
                  _buildSummaryCard(context, colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context, ColorScheme colorScheme) {
    Color statusColor;
    IconData statusIcon;
    String statusText;
    
    switch (_po!.status) {
      case 'expired':
        statusColor = Colors.red;
        statusIcon = Icons.error_outline;
        statusText = 'expired'.tr();
        break;
      case 'expiring_soon':
        statusColor = Colors.orange;
        statusIcon = Icons.warning_amber_rounded;
        statusText = 'expiring_soon'.tr();
        break;
      case 'awaiting_ordered':
        statusColor = Colors.blue;
        statusIcon = Icons.schedule;
        statusText = 'Awaiting Ordered';
        break;
      case 'material_received':
        statusColor = Colors.teal;
        statusIcon = Icons.inventory_2_outlined;
        statusText = 'Material Received';
        break;
      case 'delivery_status':
        statusColor = Colors.purple;
        statusIcon = Icons.local_shipping_outlined;
        statusText = 'Delivered';
        break;
      default:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_outline;
        statusText = 'active'.tr();
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            colorScheme.primary.withOpacity(0.8),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.description,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'purchase_order'.tr(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _po!.poNumber,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, color: statusColor, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPOInfoCard(BuildContext context, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: colorScheme.primary, size: 24),
                const SizedBox(width: 12),
                Text(
                  'po_information'.tr(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildModernInfoRow(
                  context,
                  Icons.numbers,
                  'po_number'.tr(),
                  _po!.poNumber,
                  colorScheme,
                ),
                const Divider(height: 32),
                if (_po!.quotationReference != null && _po!.quotationReference!.isNotEmpty)
                  _buildModernInfoRow(
                    context,
                    Icons.receipt_long,
                    'quotation_number'.tr(),
                    _po!.quotationReference!,
                    colorScheme,
                  ),
                if (_po!.quotationReference != null && _po!.quotationReference!.isNotEmpty)
                  const Divider(height: 32),
                _buildModernInfoRow(
                  context,
                  Icons.calendar_today,
                  'po_date'.tr(),
                  DateFormat('MMM dd, yyyy').format(_po!.poDate),
                  colorScheme,
                ),
                const Divider(height: 32),
                _buildModernInfoRow(
                  context,
                  Icons.event,
                  'expiry_date'.tr(),
                  DateFormat('MMM dd, yyyy').format(_po!.expiryDate),
                  colorScheme,
                  isExpiry: true,
                ),
                const Divider(height: 32),
                Row(
                  children: [
                    Icon(Icons.flag_outlined, color: colorScheme.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _statusOptions.any((e) => e['value'] == _po!.status)
                                ? _po!.status
                                : 'active',
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            items: _statusOptions
                                .map((e) => DropdownMenuItem<String>(
                                      value: e['value'],
                                      child: Text(e['label']!),
                                    ))
                                .toList(),
                            onChanged: _isUpdatingStatus
                                ? null
                                : (String? value) {
                                    if (value != null && value != _po!.status) {
                                      _updatePOStatus(value);
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerVendorSection(BuildContext context, ColorScheme colorScheme) {
    return Row(
      children: [
        Expanded(
          child: _buildCustomerCard(context, colorScheme),
        ),
      ],
    );
  }

  Widget _buildCustomerCard(BuildContext context, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.secondary.withOpacity(0.1),
                  colorScheme.primary.withOpacity(0.1),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.business, color: colorScheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'customer_name'.tr(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _po!.customerName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                if (_po!.customerAddress != null && _po!.customerAddress!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_on, size: 18, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _po!.customerAddress!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_po!.customerEmail != null && _po!.customerEmail!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.email, size: 18, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _po!.customerEmail!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineItemsCard(BuildContext context, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.tertiary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.list_alt, color: colorScheme.tertiary, size: 24),
                const SizedBox(width: 12),
                Text(
                  'line_items'.tr(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.tertiary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_po!.lineItems.length} ${'items'.tr()}',
                    style: TextStyle(
                      color: colorScheme.tertiary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            itemCount: _po!.lineItems.length,
            separatorBuilder: (context, index) => const Divider(height: 24),
            itemBuilder: (context, index) {
              final item = _po!.lineItems[index];
              return _buildModernLineItem(context, item, colorScheme);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModernLineItem(BuildContext context, LineItem item, ColorScheme colorScheme) {
    final currencyCode = _po!.currency;
    final currencySymbol = CurrencyHelper.getCurrencySymbol(currencyCode);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.inventory_2,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.itemName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if (item.description != null && item.description!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.description!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.secondary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${item.quantity} ${item.unit}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.secondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '×',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$currencySymbol${item.unitPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.primary.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  CurrencyHelper.formatAmount(item.total, currencyCode),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            colorScheme.primary.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.summarize,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'summary'.tr(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'total_amount'.tr(),
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  CurrencyHelper.formatAmount(_po!.totalAmount, _po!.currency),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            if (_po!.terms != null && _po!.terms!.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payment, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${'terms'.tr()}: ${_po!.terms!}',
                        style: const TextStyle(
                          color: Colors.white,
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

  Widget _buildModernInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    ColorScheme colorScheme, {
    bool isExpiry = false,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: colorScheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isExpiry && _po!.isExpired
                      ? Colors.red
                      : isExpiry && _po!.isExpiringSoon
                          ? Colors.orange
                          : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
