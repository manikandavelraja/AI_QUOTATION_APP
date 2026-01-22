import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/inquiry_provider.dart';
import '../../domain/entities/customer_inquiry.dart';
import '../../core/theme/app_theme.dart';

class InquiryListScreen extends ConsumerStatefulWidget {
  const InquiryListScreen({super.key});

  @override
  ConsumerState<InquiryListScreen> createState() => _InquiryListScreenState();
}

class _InquiryListScreenState extends ConsumerState<InquiryListScreen> {
  String _searchQuery = '';
  String _filterStatus = 'all';

  @override
  Widget build(BuildContext context) {
    final inquiryState = ref.watch(inquiryProvider);
    final allInquiries = inquiryState.inquiries;

    final filteredInquiries = allInquiries.where((inquiry) {
      final matchesSearch = _searchQuery.isEmpty ||
          inquiry.inquiryNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          inquiry.customerName.toLowerCase().contains(_searchQuery.toLowerCase());
      
      final matchesFilter = _filterStatus == 'all' ||
          (_filterStatus == 'pending' && inquiry.status == 'pending') ||
          (_filterStatus == 'reviewed' && inquiry.status == 'reviewed') ||
          (_filterStatus == 'quoted' && inquiry.status == 'quoted') ||
          (_filterStatus == 'converted_to_po' && inquiry.status == 'converted_to_po');
      
      return matchesSearch && matchesFilter;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Inquiries'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: () => context.push('/upload-inquiry'),
            tooltip: 'Upload Inquiry',
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
                    hintText: 'Search inquiries...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
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
                      _buildFilterChip('pending', 'Pending'),
                      const SizedBox(width: 8),
                      _buildFilterChip('reviewed', 'Reviewed'),
                      const SizedBox(width: 8),
                      _buildFilterChip('quoted', 'Quoted'),
                      const SizedBox(width: 8),
                      _buildFilterChip('converted_to_po', 'Converted to PO'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: inquiryState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredInquiries.isEmpty
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
                              'No inquiries found',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () =>
                            ref.read(inquiryProvider.notifier).loadInquiries(),
                        child: ListView.builder(
                          itemCount: filteredInquiries.length,
                          itemBuilder: (context, index) {
                            final inquiry = filteredInquiries[index];
                            return _buildInquiryListItem(context, inquiry);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/upload-inquiry'),
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

  Widget _buildInquiryListItem(BuildContext context, CustomerInquiry inquiry) {
    Color statusColor;
    String statusText;
    switch (inquiry.status) {
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
      case 'converted_to_po':
        statusColor = Colors.purple;
        statusText = 'Converted to PO';
        break;
      default:
        statusColor = Colors.grey;
        statusText = inquiry.status;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primaryGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.description,
            color: AppTheme.primaryGreen,
          ),
        ),
        title: Text(
          inquiry.inquiryNumber,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(inquiry.customerName),
            const SizedBox(height: 4),
            Text(
              '${inquiry.items.length} items',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
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
                statusText,
                style: const TextStyle(fontSize: 10),
              ),
              backgroundColor: statusColor.withOpacity(0.2),
              labelStyle: TextStyle(color: statusColor),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('MMM dd, yyyy').format(inquiry.inquiryDate),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        onTap: () {
          if (inquiry.id != null) {
            context.push('/inquiry-detail/${inquiry.id}');
          }
        },
      ),
    );
  }
}

