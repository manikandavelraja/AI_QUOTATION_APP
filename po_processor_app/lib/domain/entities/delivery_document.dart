import 'package:equatable/equatable.dart';

class DeliveryDocument extends Equatable {
  final String? id;
  final String documentNumber;
  final String documentType; // 'commercial_invoice', 'delivery_order', 'both'
  final DateTime documentDate;
  final String customerName;
  final String? customerAddress;
  final String? customerEmail;
  final String? customerPhone;
  final String? customerTRN; // Tax Registration Number
  final List<DeliveryItem> items;
  final double subtotal;
  final double? vatAmount; // VAT/Tax amount
  final double totalAmount;
  final String? currency;
  final String? terms;
  final String? notes;
  final String? pdfPath;
  final String status; // 'draft', 'generated', 'sent'
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? poId; // Link to customer PO
  final String? supplierOrderId; // Link to supplier order

  const DeliveryDocument({
    this.id,
    required this.documentNumber,
    required this.documentType,
    required this.documentDate,
    required this.customerName,
    this.customerAddress,
    this.customerEmail,
    this.customerPhone,
    this.customerTRN,
    required this.items,
    required this.subtotal,
    this.vatAmount,
    required this.totalAmount,
    this.currency,
    this.terms,
    this.notes,
    this.pdfPath,
    this.status = 'draft',
    required this.createdAt,
    this.updatedAt,
    this.poId,
    this.supplierOrderId,
  });

  DeliveryDocument copyWith({
    String? id,
    String? documentNumber,
    String? documentType,
    DateTime? documentDate,
    String? customerName,
    String? customerAddress,
    String? customerEmail,
    String? customerPhone,
    String? customerTRN,
    List<DeliveryItem>? items,
    double? subtotal,
    double? vatAmount,
    double? totalAmount,
    String? currency,
    String? terms,
    String? notes,
    String? pdfPath,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? poId,
    String? supplierOrderId,
  }) {
    return DeliveryDocument(
      id: id ?? this.id,
      documentNumber: documentNumber ?? this.documentNumber,
      documentType: documentType ?? this.documentType,
      documentDate: documentDate ?? this.documentDate,
      customerName: customerName ?? this.customerName,
      customerAddress: customerAddress ?? this.customerAddress,
      customerEmail: customerEmail ?? this.customerEmail,
      customerPhone: customerPhone ?? this.customerPhone,
      customerTRN: customerTRN ?? this.customerTRN,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      vatAmount: vatAmount ?? this.vatAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      currency: currency ?? this.currency,
      terms: terms ?? this.terms,
      notes: notes ?? this.notes,
      pdfPath: pdfPath ?? this.pdfPath,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      poId: poId ?? this.poId,
      supplierOrderId: supplierOrderId ?? this.supplierOrderId,
    );
  }

  @override
  List<Object?> get props => [
        id,
        documentNumber,
        documentType,
        documentDate,
        customerName,
        customerAddress,
        customerEmail,
        customerPhone,
        customerTRN,
        items,
        subtotal,
        vatAmount,
        totalAmount,
        currency,
        terms,
        notes,
        pdfPath,
        status,
        createdAt,
        updatedAt,
        poId,
        supplierOrderId,
      ];
}

class DeliveryItem extends Equatable {
  final String? id;
  final String itemName;
  final String? itemCode;
  final String? description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double total;

  const DeliveryItem({
    this.id,
    required this.itemName,
    this.itemCode,
    this.description,
    required this.quantity,
    this.unit = 'EA',
    required this.unitPrice,
    required this.total,
  });

  DeliveryItem copyWith({
    String? id,
    String? itemName,
    String? itemCode,
    String? description,
    double? quantity,
    String? unit,
    double? unitPrice,
    double? total,
  }) {
    return DeliveryItem(
      id: id ?? this.id,
      itemName: itemName ?? this.itemName,
      itemCode: itemCode ?? this.itemCode,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      total: total ?? this.total,
    );
  }

  @override
  List<Object?> get props => [
        id,
        itemName,
        itemCode,
        description,
        quantity,
        unit,
        unitPrice,
        total,
      ];
}

