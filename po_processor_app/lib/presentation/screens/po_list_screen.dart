import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/po_provider.dart';
import '../../domain/entities/purchase_order.dart';
import '../../core/utils/currency_helper.dart';

class POListScreen extends ConsumerStatefulWidget {
  const POListScreen({super.key});

  @override
  ConsumerState<POListScreen> createState() => _POListScreenState();
}

class _POListScreenState extends ConsumerState<POListScreen> with SingleTickerProviderStateMixin {
  String _searchQuery = '';
  String _filterStatus = 'all';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final poState = ref.watch(poProvider);
    final allPOs = poState.purchaseOrders;

    // Filter by search query
    final searchFiltered = allPOs.where((po) {
      return _searchQuery.isEmpty ||
          po.poNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          po.customerName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // Filter by tab selection
    final filteredPOs = searchFiltered.where((po) {
      switch (_tabController.index) {
        case 0: // All
          return true;
        case 1: // Active
          return po.status == 'active';
        case 2: // Awaiting Ordered
          return po.status == 'awaiting_ordered';
        case 3: // Material Received
          return po.status == 'material_received';
        case 4: // Delivery Status
          return po.status == 'delivery_status';
        default:
          return true;
      }
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('po_list'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(poProvider.notifier).loadPurchaseOrders(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'search'.tr(),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'Active'),
              Tab(text: 'Awaiting Ordered'),
              Tab(text: 'Material Received'),
              Tab(text: 'Delivery Status'),
            ],
            onTap: (index) {
              setState(() {});
            },
          ),
          Expanded(
            child: poState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredPOs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'no_data'.tr(),
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () =>
                            ref.read(poProvider.notifier).loadPurchaseOrders(),
                        child: ListView.builder(
                          itemCount: filteredPOs.length,
                          itemBuilder: (context, index) {
                            final po = filteredPOs[index];
                            return _buildPOListItem(context, po);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/upload'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filterStatus == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterStatus = value;
        });
      },
    );
  }

  Widget _buildPOListItem(BuildContext context, PurchaseOrder po) {
    Color statusColor;
    IconData statusIcon;
    
    switch (po.status) {
      case 'expired':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case 'expiring_soon':
        statusColor = Colors.orange;
        statusIcon = Icons.warning;
        break;
      default:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.2),
          child: Icon(statusIcon, color: statusColor),
        ),
        title: Text(
          po.poNumber,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(po.customerName),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  DateFormat('MMM dd, yyyy').format(po.poDate),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Text(' • '),
                Text(
                  CurrencyHelper.formatAmount(po.totalAmount, po.currency),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              DateFormat('MMM dd').format(po.expiryDate),
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              po.status.tr(),
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
        onTap: () => context.push('/po-detail/${po.id}'),
      ),
    );
  }
}

