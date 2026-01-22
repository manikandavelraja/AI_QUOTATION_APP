import 'package:equatable/equatable.dart';

class PurchaseOrder extends Equatable {
  final String? id;
  final String poNumber;
  final DateTime poDate;
  final DateTime expiryDate;
  final String customerName;
  final String? customerAddress;
  final String? customerEmail;
  final double totalAmount;
  final String? currency; // Currency code (AED, INR, USD, etc.)
  final String? terms;
  final String? notes;
  final List<LineItem> lineItems;
  final String? pdfPath;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String status; // 'active', 'expired', 'expiring_soon'

  const PurchaseOrder({
    this.id,
    required this.poNumber,
    required this.poDate,
    required this.expiryDate,
    required this.customerName,
    this.customerAddress,
    this.customerEmail,
    required this.totalAmount,
    this.currency,
    this.terms,
    this.notes,
    required this.lineItems,
    this.pdfPath,
    required this.createdAt,
    this.updatedAt,
    this.status = 'active',
  });

  bool get isExpiringSoon {
    final daysUntilExpiry = expiryDate.difference(DateTime.now()).inDays;
    return daysUntilExpiry <= 7 && daysUntilExpiry >= 0;
  }

  bool get isExpired {
    return expiryDate.isBefore(DateTime.now());
  }

  PurchaseOrder copyWith({
    String? id,
    String? poNumber,
    DateTime? poDate,
    DateTime? expiryDate,
    String? customerName,
    String? customerAddress,
    String? customerEmail,
    double? totalAmount,
    String? currency,
    String? terms,
    String? notes,
    List<LineItem>? lineItems,
    String? pdfPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? status,
  }) {
    return PurchaseOrder(
      id: id ?? this.id,
      poNumber: poNumber ?? this.poNumber,
      poDate: poDate ?? this.poDate,
      expiryDate: expiryDate ?? this.expiryDate,
      customerName: customerName ?? this.customerName,
      customerAddress: customerAddress ?? this.customerAddress,
      customerEmail: customerEmail ?? this.customerEmail,
      totalAmount: totalAmount ?? this.totalAmount,
      currency: currency ?? this.currency,
      terms: terms ?? this.terms,
      notes: notes ?? this.notes,
      lineItems: lineItems ?? this.lineItems,
      pdfPath: pdfPath ?? this.pdfPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [
        id,
        poNumber,
        poDate,
        expiryDate,
        customerName,
        customerAddress,
        customerEmail,
        totalAmount,
        currency,
        terms,
        notes,
        lineItems,
        pdfPath,
        createdAt,
        updatedAt,
        status,
      ];
}

class LineItem extends Equatable {
  final String? id;
  final String itemName;
  final String? itemCode;
  final String? description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double total;

  const LineItem({
    this.id,
    required this.itemName,
    this.itemCode,
    this.description,
    required this.quantity,
    this.unit = 'pcs',
    required this.unitPrice,
    required this.total,
  });

  LineItem copyWith({
    String? id,
    String? itemName,
    String? itemCode,
    String? description,
    double? quantity,
    String? unit,
    double? unitPrice,
    double? total,
  }) {
    return LineItem(
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

