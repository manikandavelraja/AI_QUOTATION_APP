import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/delivery_provider.dart';
import '../../domain/entities/delivery_document.dart';
import '../../core/utils/currency_helper.dart';

class DeliveryDocumentListScreen extends ConsumerWidget {
  const DeliveryDocumentListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(deliveryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Documents'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/delivery-document-create'),
            tooltip: 'Create Delivery Document',
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.documents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No Delivery Documents',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => context.push('/delivery-document-create'),
                        child: const Text('Create First Document'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.read(deliveryProvider.notifier).loadDeliveryDocuments(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.documents.length,
                    itemBuilder: (context, index) {
                      final doc = state.documents[index];
                      return _buildDocumentCard(context, doc);
                    },
                  ),
                ),
    );
  }

  Widget _buildDocumentCard(BuildContext context, DeliveryDocument doc) {
    Color statusColor;
    IconData docIcon;
    String docTypeText;
    
    switch (doc.documentType) {
      case 'commercial_invoice':
        docIcon = Icons.receipt;
        docTypeText = 'Commercial Invoice';
        break;
      case 'delivery_order':
        docIcon = Icons.local_shipping;
        docTypeText = 'Delivery Order';
        break;
      case 'both':
        docIcon = Icons.description;
        docTypeText = 'Both';
        break;
      default:
        docIcon = Icons.description;
        docTypeText = doc.documentType;
    }
    
    switch (doc.status) {
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
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(docIcon, color: statusColor),
        ),
        title: Text(
          doc.documentNumber,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(doc.customerName),
            const SizedBox(height: 4),
            Text(
              docTypeText,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              CurrencyHelper.formatAmount(doc.totalAmount, doc.currency),
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
                doc.status.toUpperCase(),
                style: const TextStyle(fontSize: 10),
              ),
              backgroundColor: statusColor.withOpacity(0.2),
              labelStyle: TextStyle(color: statusColor),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('MMM dd, yyyy').format(doc.documentDate),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        onTap: () => context.push('/delivery-document-detail/${doc.id}'),
      ),
    );
  }
}

