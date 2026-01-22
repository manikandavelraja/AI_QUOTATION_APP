import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/quotation_provider.dart';
import '../../domain/entities/quotation.dart';
import '../../core/utils/currency_helper.dart';

class QuotationListScreen extends ConsumerStatefulWidget {
  const QuotationListScreen({super.key});

  @override
  ConsumerState<QuotationListScreen> createState() => _QuotationListScreenState();
}

class _QuotationListScreenState extends ConsumerState<QuotationListScreen> {
  String _searchQuery = '';
  String _filterStatus = 'all';

  @override
  Widget build(BuildContext context) {
    final quotationState = ref.watch(quotationProvider);
    final allQuotations = quotationState.quotations;

    final filteredQuotations = allQuotations.where((quotation) {
      final matchesSearch = _searchQuery.isEmpty ||
          quotation.quotationNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          quotation.customerName.toLowerCase().contains(_searchQuery.toLowerCase());
      
      final matchesFilter = _filterStatus == 'all' ||
          (_filterStatus == 'draft' && quotation.status == 'draft') ||
          (_filterStatus == 'sent' && quotation.status == 'sent') ||
          (_filterStatus == 'accepted' && quotation.status == 'accepted') ||
          (_filterStatus == 'rejected' && quotation.status == 'rejected') ||
          (_filterStatus == 'expired' && quotation.status == 'expired');
      
      return matchesSearch && matchesFilter;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quotations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(quotationProvider.notifier).loadQuotations(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Search',
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
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('all', 'All'),
                      const SizedBox(width: 8),
                      _buildFilterChip('draft', 'Draft'),
                      const SizedBox(width: 8),
                      _buildFilterChip('sent', 'Sent'),
                      const SizedBox(width: 8),
                      _buildFilterChip('accepted', 'Accepted'),
                      const SizedBox(width: 8),
                      _buildFilterChip('rejected', 'Rejected'),
                      const SizedBox(width: 8),
                      _buildFilterChip('expired', 'Expired'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: quotationState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredQuotations.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.description_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No quotations found',
                              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref.read(quotationProvider.notifier).loadQuotations(),
                        child: ListView.builder(
                          itemCount: filteredQuotations.length,
                          itemBuilder: (context, index) {
                            final quotation = filteredQuotations[index];
                            return _buildQuotationListItem(context, quotation);
                          },
                        ),
                      ),
          ),
        ],
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

  Widget _buildQuotationListItem(BuildContext context, Quotation quotation) {
    Color statusColor;
    switch (quotation.status) {
      case 'draft':
        statusColor = Colors.orange;
        break;
      case 'sent':
        statusColor = Colors.blue;
        break;
      case 'accepted':
        statusColor = Colors.green;
        break;
      case 'rejected':
        statusColor = Colors.red;
        break;
      case 'expired':
        statusColor = Colors.grey;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.description, color: statusColor),
        ),
        title: Text(
          quotation.quotationNumber,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(quotation.customerName),
            const SizedBox(height: 4),
            Text(
              CurrencyHelper.formatAmount(quotation.totalAmount, quotation.currency),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Chip(
              label: Text(
                quotation.status.toUpperCase(),
                style: const TextStyle(fontSize: 10),
              ),
              backgroundColor: statusColor.withOpacity(0.2),
              labelStyle: TextStyle(color: statusColor),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('MMM dd, yyyy').format(quotation.quotationDate),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        onTap: () => context.push('/quotation-detail/${quotation.id}'),
      ),
    );
  }
}

