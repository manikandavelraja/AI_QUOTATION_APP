import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/quotation_provider.dart';
import '../../domain/entities/quotation.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/theme/app_theme.dart';

class QuotationListScreen extends ConsumerStatefulWidget {
  /// When true, renders only the list content (no Scaffold/AppBar) for embedding in dashboard.
  final bool embedInDashboard;

  const QuotationListScreen({super.key, this.embedInDashboard = false});

  @override
  ConsumerState<QuotationListScreen> createState() => _QuotationListScreenState();
}

class _QuotationListScreenState extends ConsumerState<QuotationListScreen> {
  String _searchQuery = '';
  String _filterStatus = 'all';
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  /// null = all months; otherwise filter by this month (quotationDate)
  DateTime? _selectedMonth;
  /// null = all weeks; otherwise filter by this week (Monday as start of week)
  DateTime? _selectedWeek;

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelectAll(List<Quotation> list) {
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
        title: const Text('Delete quotations?'),
        content: Text(
          'Delete ${_selectedIds.length} quotation(s)? This cannot be undone.',
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
    final notifier = ref.read(quotationProvider.notifier);
    for (final id in _selectedIds) {
      await notifier.deleteQuotation(id);
    }
    if (mounted) {
      _exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count quotation(s) deleted')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final quotationState = ref.watch(quotationProvider);
    final allQuotations = quotationState.quotations;

    // Month filter by quotationDate
    final monthFiltered = _selectedMonth == null
        ? allQuotations
        : allQuotations.where((q) {
            return q.quotationDate.year == _selectedMonth!.year &&
                q.quotationDate.month == _selectedMonth!.month;
          }).toList();

    // Week filter (Monday = start of week)
    final weekFiltered = _selectedWeek == null
        ? monthFiltered
        : monthFiltered.where((q) {
            final qStart = _startOfWeek(q.quotationDate);
            return qStart.year == _selectedWeek!.year &&
                qStart.month == _selectedWeek!.month &&
                qStart.day == _selectedWeek!.day;
          }).toList();

    final filteredQuotations = weekFiltered.where((quotation) {
      final matchesSearch = _searchQuery.isEmpty ||
          quotation.quotationNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          quotation.customerName.toLowerCase().contains(_searchQuery.toLowerCase());
      
      final hasPendingItems = quotation.items.any((item) => item.status == 'pending' || item.unitPrice == 0);
      
      // Expired chip removed - no filter for 'expired'
      final matchesFilter = _filterStatus == 'all' ||
          (_filterStatus == 'draft' && quotation.status == 'draft') ||
          (_filterStatus == 'sent' && quotation.status == 'sent') ||
          (_filterStatus == 'pending' && hasPendingItems);
      
      return matchesSearch && matchesFilter;
    }).toList();

    final bodyContent = Column(
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Filter by month',
                          prefixIcon: const Icon(Icons.calendar_month, size: 22),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<DateTime?>(
                            value: _selectedMonth,
                            isExpanded: true,
                            hint: const Text('All months'),
                            items: [
                              const DropdownMenuItem<DateTime?>(
                                value: null,
                                child: Text('All months'),
                              ),
                              ..._buildMonthDropdownItems(allQuotations),
                            ],
                            onChanged: (value) {
                              setState(() => _selectedMonth = value);
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Filter by week',
                          prefixIcon: const Icon(Icons.date_range, size: 22),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<DateTime?>(
                            value: _selectedWeek,
                            isExpanded: true,
                            hint: const Text('All weeks'),
                            items: _buildWeekDropdownItems(),
                            onChanged: (value) {
                              setState(() => _selectedWeek = value);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
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
                      _buildFilterChip('pending', 'Pending'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${filteredQuotations.length} quotation(s)',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
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
                            Icon(Icons.description_outlined, size: 64, color: AppTheme.textSecondary),
                            const SizedBox(height: 16),
                            Text(
                              'No quotations found',
                              style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
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
                            return _buildQuotationListItem(
                              context,
                              quotation,
                              isSelected: quotation.id != null && _selectedIds.contains(quotation.id),
                              isSelectionMode: _isSelectionMode,
                              onTap: () {
                                if (_isSelectionMode && quotation.id != null) {
                                  setState(() {
                                    if (_selectedIds.contains(quotation.id)) {
                                      _selectedIds.remove(quotation.id);
                                    } else {
                                      _selectedIds.add(quotation.id!);
                                    }
                                  });
                                } else {
                                  context.push('/quotation-detail/${quotation.id}');
                                }
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      );

    if (widget.embedInDashboard) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Text(
                  'View All Quotations',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                if (_isSelectionMode) ...[
                  TextButton(
                    onPressed: _exitSelectionMode,
                    child: const Text('Cancel'),
                  ),
                  TextButton.icon(
                    onPressed: () => _toggleSelectAll(filteredQuotations),
                    icon: const Icon(Icons.select_all, size: 20),
                    label: Text(
                      _selectedIds.length == filteredQuotations.length && filteredQuotations.isNotEmpty
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
                    onPressed: () => ref.read(quotationProvider.notifier).loadQuotations(),
                    tooltip: 'Refresh',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _isSelectionMode = true),
                    tooltip: 'Delete quotations',
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: bodyContent),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode ? 'Select quotations' : 'Quotations'),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
                tooltip: 'Cancel',
              )
            : null,
        actions: [
          if (_isSelectionMode) ...[
            TextButton.icon(
              onPressed: () => _toggleSelectAll(filteredQuotations),
              icon: const Icon(Icons.select_all, size: 20),
              label: Text(
                _selectedIds.length == filteredQuotations.length && filteredQuotations.isNotEmpty
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
              onPressed: () => ref.read(quotationProvider.notifier).loadQuotations(),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => _isSelectionMode = true),
              tooltip: 'Delete quotations',
            ),
          ],
        ],
      ),
      body: bodyContent,
    );
  }

  static DateTime _startOfWeek(DateTime d) {
    return DateTime(d.year, d.month, d.day - (d.weekday - 1));
  }

  List<DropdownMenuItem<DateTime?>> _buildWeekDropdownItems() {
    const nullItem = DropdownMenuItem<DateTime?>(
      value: null,
      child: Text('All weeks'),
    );
    final now = DateTime.now();
    final thisWeek = _startOfWeek(now);
    final lastWeek = thisWeek.subtract(const Duration(days: 7));
    final twoWeeksAgo = thisWeek.subtract(const Duration(days: 14));
    final threeWeeksAgo = thisWeek.subtract(const Duration(days: 21));
    return [
      nullItem,
      DropdownMenuItem<DateTime?>(
        value: thisWeek,
        child: Text('This week (${DateFormat('MMM d').format(thisWeek)})'),
      ),
      DropdownMenuItem<DateTime?>(
        value: lastWeek,
        child: Text('Last week (${DateFormat('MMM d').format(lastWeek)})'),
      ),
      DropdownMenuItem<DateTime?>(
        value: twoWeeksAgo,
        child: Text('2 weeks ago (${DateFormat('MMM d').format(twoWeeksAgo)})'),
      ),
      DropdownMenuItem<DateTime?>(
        value: threeWeeksAgo,
        child: Text('3 weeks ago (${DateFormat('MMM d').format(threeWeeksAgo)})'),
      ),
    ];
  }

  List<DropdownMenuItem<DateTime?>> _buildMonthDropdownItems(List<Quotation> list) {
    final months = <DateTime>{};
    for (final q in list) {
      months.add(DateTime(q.quotationDate.year, q.quotationDate.month));
    }
    final sorted = months.toList()..sort((a, b) => b.compareTo(a));
    return sorted
        .map((d) => DropdownMenuItem<DateTime?>(
              value: d,
              child: Text(DateFormat('MMMM yyyy').format(d)),
            ))
        .toList();
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filterStatus == value;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : null,
          fontWeight: isSelected ? FontWeight.w600 : null,
        ),
      ),
      selected: isSelected,
      selectedColor: AppTheme.primaryGreen,
      checkmarkColor: Colors.white,
      onSelected: (selected) {
        setState(() {
          _filterStatus = value;
        });
      },
    );
  }

  Widget _buildQuotationListItem(
    BuildContext context,
    Quotation quotation, {
    required bool isSelected,
    required bool isSelectionMode,
    required VoidCallback onTap,
  }) {
    final hasPendingItems = quotation.items.any((item) => item.status == 'pending' || item.unitPrice == 0);
    final pendingItems = quotation.items.where((item) => item.status == 'pending' || item.unitPrice == 0).toList();
    final displayStatus = hasPendingItems ? 'pending' : quotation.status;
    
    Color statusColor;
    switch (displayStatus) {
      case 'draft':
        statusColor = Colors.orange;
        break;
      case 'sent':
        statusColor = Colors.blue;
        break;
      case 'pending':
        statusColor = Colors.yellow;
        break;
      case 'accepted':
        statusColor = Colors.green;
        break;
      case 'rejected':
        statusColor = Colors.red;
        break;
      case 'expired':
        statusColor = AppTheme.textSecondary;
        break;
      default:
        statusColor = AppTheme.textSecondary;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isSelected ? statusColor.withOpacity(0.08) : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSelectionMode) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: quotation.id == null
                        ? null
                        : (_) => onTap(),
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
              // Leading icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.description, color: statusColor),
              ),
              const SizedBox(width: 16),
              // Main content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      quotation.quotationNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      quotation.customerName,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.dashboardText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyHelper.formatAmount(quotation.totalAmount, quotation.currency),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    // Show pending items note
                    if (hasPendingItems && pendingItems.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.yellow.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.yellow.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Note: Some items pending',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.yellow[800],
                              ),
                            ),
                            const SizedBox(height: 4),
                            ...pendingItems.take(3).map((item) {
                              final itemCode = item.itemCode?.isNotEmpty == true ? item.itemCode! : 'N/A';
                              return Padding(
                                padding: const EdgeInsets.only(left: 4, top: 2),
                                child: Text(
                                  '• ${item.itemName} (Code: $itemCode)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.yellow[900],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                            if (pendingItems.length > 3)
                              Padding(
                                padding: const EdgeInsets.only(left: 4, top: 2),
                                child: Text(
                                  '... and ${pendingItems.length - 3} more',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.yellow[900],
                                    fontStyle: FontStyle.italic,
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
              const SizedBox(width: 8),
              // Trailing status and date
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Chip(
                    label: Text(
                      displayStatus.toUpperCase(),
                      style: const TextStyle(fontSize: 10),
                    ),
                    backgroundColor: statusColor.withOpacity(0.2),
                    labelStyle: TextStyle(color: statusColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM dd, yyyy').format(quotation.quotationDate),
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

