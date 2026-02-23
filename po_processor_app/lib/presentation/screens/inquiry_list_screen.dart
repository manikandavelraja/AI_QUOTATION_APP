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
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelectAll(List<CustomerInquiry> list) {
    final ids = list.map((q) => q.id).whereType<String>().toSet();
    setState(() {
      if (_selectedIds.length == ids.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete inquiries?'),
        content: Text(
          'Delete ${_selectedIds.length} inquiry(ies)? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final count = _selectedIds.length;
    final notifier = ref.read(inquiryProvider.notifier);
    for (final id in _selectedIds) {
      await notifier.deleteInquiry(id);
    }
    if (mounted) {
      _exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count inquiry(ies) deleted')),
      );
    }
  }

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
          (_filterStatus == 'quoted' && (inquiry.status == 'quoted' || inquiry.status == 'partially_quoted')) ||
          (_filterStatus == 'partially_quoted' && inquiry.status == 'partially_quoted') ||
          (_filterStatus == 'converted_to_po' && inquiry.status == 'converted_to_po');
      
      return matchesSearch && matchesFilter;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
                tooltip: 'Cancel',
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/dashboard'),
                tooltip: 'Back to Home',
              ),
        title: Text(_isSelectionMode ? 'Select inquiries' : 'Customer Inquiries'),
        actions: [
          if (_isSelectionMode) ...[
            TextButton.icon(
              onPressed: () => _toggleSelectAll(filteredInquiries),
              icon: const Icon(Icons.select_all, size: 20),
              label: Text(
                _selectedIds.length == filteredInquiries.length && filteredInquiries.isNotEmpty
                    ? 'Deselect All'
                    : 'Select All',
              ),
            ),
            IconButton(
              icon: Badge(
                isLabelVisible: _selectedIds.isNotEmpty,
                label: Text('${_selectedIds.length}'),
                child: const Icon(Icons.delete_outline),
              ),
              onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
              tooltip: 'Delete selected',
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(inquiryProvider.notifier).loadInquiries(),
            ),
            IconButton(
              icon: const Icon(Icons.upload_file),
              onPressed: () => context.push('/upload-inquiry'),
              tooltip: 'Upload Inquiry',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => _isSelectionMode = true),
              tooltip: 'Delete inquiries',
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
        onRefresh: () => ref.read(inquiryProvider.notifier).loadInquiries(),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                          _buildFilterChip('partially_quoted', 'Partially Quoted'),
                          const SizedBox(width: 8),
                          _buildFilterChip('converted_to_po', 'Converted to PO'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (inquiryState.isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filteredInquiries.isEmpty)
              SliverFillRemaining(
                child: Center(
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
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 80),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final inquiry = filteredInquiries[index];
                      final isSelected = inquiry.id != null && _selectedIds.contains(inquiry.id);
                      return _buildInquiryListItem(
                        context,
                        inquiry,
                        isSelected: isSelected,
                        isSelectionMode: _isSelectionMode,
                        onTap: () {
                          if (_isSelectionMode && inquiry.id != null) {
                            setState(() {
                              if (_selectedIds.contains(inquiry.id)) {
                                _selectedIds.remove(inquiry.id);
                              } else {
                                _selectedIds.add(inquiry.id!);
                              }
                            });
                          } else if (inquiry.id != null) {
                            context.push('/inquiry-detail/${inquiry.id}');
                          }
                        },
                      );
                    },
                    childCount: filteredInquiries.length,
                  ),
                ),
              ),
          ],
        ),
        ),
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

  Widget _buildInquiryListItem(
    BuildContext context,
    CustomerInquiry inquiry, {
    required bool isSelected,
    required bool isSelectionMode,
    required VoidCallback onTap,
  }) {
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
        statusText = inquiry.status;
    }
    final quotedCount = inquiry.items.where((i) => i.status == 'quoted').length;
    final pendingCount = inquiry.items.length - quotedCount;
    final itemSummary = inquiry.items.isEmpty
        ? '0 items'
        : (inquiry.status == 'partially_quoted' && pendingCount > 0 && quotedCount > 0)
            ? '${inquiry.items.length} items ($quotedCount quoted, $pendingCount pending)'
            : '${inquiry.items.length} items';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: isSelected ? statusColor.withOpacity(0.08) : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelectionMode) ...[
              Checkbox(
                value: isSelected,
                onChanged: inquiry.id == null
                    ? null
                    : (_) => onTap(),
                activeColor: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
            ],
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.description,
                color: AppTheme.primaryGreen,
                size: 22,
              ),
            ),
          ],
        ),
        title: Text(
          inquiry.inquiryNumber,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 2),
            Text(
              inquiry.customerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              itemSummary,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 100),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(height: 2),
              Text(
                DateFormat('MMM dd, yyyy').format(inquiry.inquiryDate),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ],
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

