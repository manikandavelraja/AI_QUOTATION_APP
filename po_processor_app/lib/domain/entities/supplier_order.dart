import 'package:equatable/equatable.dart';

class SupplierOrder extends Equatable {
  final String? id;
  final String orderNumber;
  final DateTime orderDate;
  final DateTime? expectedDeliveryDate;
  final String supplierName;
  final String? supplierAddress;
  final String? supplierEmail;
  final String? supplierPhone;
  final List<SupplierOrderItem> items;
  final double totalAmount;
  final String? currency;
  final String? terms;
  final String? notes;
  final String status; // 'pending', 'confirmed', 'in_transit', 'delivered', 'cancelled'
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? poId; // Link to customer PO
  final String? deliveryDocumentId; // Link to delivery document when received

  const SupplierOrder({
    this.id,
    required this.orderNumber,
    required this.orderDate,
    this.expectedDeliveryDate,
    required this.supplierName,
    this.supplierAddress,
    this.supplierEmail,
    this.supplierPhone,
    required this.items,
    required this.totalAmount,
    this.currency,
    this.terms,
    this.notes,
    this.status = 'pending',
    required this.createdAt,
    this.updatedAt,
    this.poId,
    this.deliveryDocumentId,
  });

  SupplierOrder copyWith({
    String? id,
    String? orderNumber,
    DateTime? orderDate,
    DateTime? expectedDeliveryDate,
    String? supplierName,
    String? supplierAddress,
    String? supplierEmail,
    String? supplierPhone,
    List<SupplierOrderItem>? items,
    double? totalAmount,
    String? currency,
    String? terms,
    String? notes,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? poId,
    String? deliveryDocumentId,
  }) {
    return SupplierOrder(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      orderDate: orderDate ?? this.orderDate,
      expectedDeliveryDate: expectedDeliveryDate ?? this.expectedDeliveryDate,
      supplierName: supplierName ?? this.supplierName,
      supplierAddress: supplierAddress ?? this.supplierAddress,
      supplierEmail: supplierEmail ?? this.supplierEmail,
      supplierPhone: supplierPhone ?? this.supplierPhone,
      items: items ?? this.items,
      totalAmount: totalAmount ?? this.totalAmount,
      currency: currency ?? this.currency,
      terms: terms ?? this.terms,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      poId: poId ?? this.poId,
      deliveryDocumentId: deliveryDocumentId ?? this.deliveryDocumentId,
    );
  }

  @override
  List<Object?> get props => [
        id,
        orderNumber,
        orderDate,
        expectedDeliveryDate,
        supplierName,
        supplierAddress,
        supplierEmail,
        supplierPhone,
        items,
        totalAmount,
        currency,
        terms,
        notes,
        status,
        createdAt,
        updatedAt,
        poId,
        deliveryDocumentId,
      ];
}

class SupplierOrderItem extends Equatable {
  final String? id;
  final String itemName;
  final String? itemCode;
  final String? description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double total;

  const SupplierOrderItem({
    this.id,
    required this.itemName,
    this.itemCode,
    this.description,
    required this.quantity,
    this.unit = 'EA',
    required this.unitPrice,
    required this.total,
  });

  SupplierOrderItem copyWith({
    String? id,
    String? itemName,
    String? itemCode,
    String? description,
    double? quantity,
    String? unit,
    double? unitPrice,
    double? total,
  }) {
    return SupplierOrderItem(
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

