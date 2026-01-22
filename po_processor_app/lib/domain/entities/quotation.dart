import 'package:equatable/equatable.dart';

class Quotation extends Equatable {
  final String? id;
  final String quotationNumber;
  final DateTime quotationDate;
  final DateTime validityDate;
  final String customerName;
  final String? customerAddress;
  final String? customerEmail;
  final String? customerPhone;
  final List<QuotationItem> items;
  final double totalAmount;
  final String? currency;
  final String? terms;
  final String? notes;
  final String? pdfPath;
  final String status; // 'draft', 'sent', 'accepted', 'rejected', 'expired'
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? inquiryId; // Link to inquiry
  final String? poId; // Link to PO if accepted

  const Quotation({
    this.id,
    required this.quotationNumber,
    required this.quotationDate,
    required this.validityDate,
    required this.customerName,
    this.customerAddress,
    this.customerEmail,
    this.customerPhone,
    required this.items,
    required this.totalAmount,
    this.currency,
    this.terms,
    this.notes,
    this.pdfPath,
    this.status = 'draft',
    required this.createdAt,
    this.updatedAt,
    this.inquiryId,
    this.poId,
  });

  bool get isExpired {
    return validityDate.isBefore(DateTime.now());
  }

  bool get isExpiringSoon {
    final daysUntilExpiry = validityDate.difference(DateTime.now()).inDays;
    return daysUntilExpiry <= 7 && daysUntilExpiry >= 0;
  }

  Quotation copyWith({
    String? id,
    String? quotationNumber,
    DateTime? quotationDate,
    DateTime? validityDate,
    String? customerName,
    String? customerAddress,
    String? customerEmail,
    String? customerPhone,
    List<QuotationItem>? items,
    double? totalAmount,
    String? currency,
    String? terms,
    String? notes,
    String? pdfPath,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? inquiryId,
    String? poId,
  }) {
    return Quotation(
      id: id ?? this.id,
      quotationNumber: quotationNumber ?? this.quotationNumber,
      quotationDate: quotationDate ?? this.quotationDate,
      validityDate: validityDate ?? this.validityDate,
      customerName: customerName ?? this.customerName,
      customerAddress: customerAddress ?? this.customerAddress,
      customerEmail: customerEmail ?? this.customerEmail,
      customerPhone: customerPhone ?? this.customerPhone,
      items: items ?? this.items,
      totalAmount: totalAmount ?? this.totalAmount,
      currency: currency ?? this.currency,
      terms: terms ?? this.terms,
      notes: notes ?? this.notes,
      pdfPath: pdfPath ?? this.pdfPath,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      inquiryId: inquiryId ?? this.inquiryId,
      poId: poId ?? this.poId,
    );
  }

  @override
  List<Object?> get props => [
        id,
        quotationNumber,
        quotationDate,
        validityDate,
        customerName,
        customerAddress,
        customerEmail,
        customerPhone,
        items,
        totalAmount,
        currency,
        terms,
        notes,
        pdfPath,
        status,
        createdAt,
        updatedAt,
        inquiryId,
        poId,
      ];
}

class QuotationItem extends Equatable {
  final String? id;
  final String itemName;
  final String? itemCode;
  final String? description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double total;
  final String? manufacturerPart;

  const QuotationItem({
    this.id,
    required this.itemName,
    this.itemCode,
    this.description,
    required this.quantity,
    this.unit = 'EA',
    required this.unitPrice,
    required this.total,
    this.manufacturerPart,
  });

  QuotationItem copyWith({
    String? id,
    String? itemName,
    String? itemCode,
    String? description,
    double? quantity,
    String? unit,
    double? unitPrice,
    double? total,
    String? manufacturerPart,
  }) {
    return QuotationItem(
      id: id ?? this.id,
      itemName: itemName ?? this.itemName,
      itemCode: itemCode ?? this.itemCode,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      total: total ?? this.total,
      manufacturerPart: manufacturerPart ?? this.manufacturerPart,
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
        manufacturerPart,
      ];
}

