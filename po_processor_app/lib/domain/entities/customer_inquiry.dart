import 'package:equatable/equatable.dart';

class CustomerInquiry extends Equatable {
  final String? id;
  final String inquiryNumber; // RFQ number or inquiry reference
  final DateTime inquiryDate;
  final String customerName;
  final String? customerAddress;
  final String? customerEmail;
  final String? customerPhone;
  final String? senderEmail; // Email address of the sender (from GetFromMail)
  final List<InquiryItem> items;
  final String? notes;
  final String? pdfPath;
  final String status; // 'pending', 'reviewed', 'quoted', 'converted_to_po'
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? quotationId; // Link to quotation if created
  final String? poId; // Link to PO if converted

  const CustomerInquiry({
    this.id,
    required this.inquiryNumber,
    required this.inquiryDate,
    required this.customerName,
    this.customerAddress,
    this.customerEmail,
    this.customerPhone,
    this.senderEmail,
    required this.items,
    this.notes,
    this.pdfPath,
    this.status = 'pending',
    required this.createdAt,
    this.updatedAt,
    this.quotationId,
    this.poId,
  });

  CustomerInquiry copyWith({
    String? id,
    String? inquiryNumber,
    DateTime? inquiryDate,
    String? customerName,
    String? customerAddress,
    String? customerEmail,
    String? customerPhone,
    String? senderEmail,
    List<InquiryItem>? items,
    String? notes,
    String? pdfPath,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? quotationId,
    String? poId,
  }) {
    return CustomerInquiry(
      id: id ?? this.id,
      inquiryNumber: inquiryNumber ?? this.inquiryNumber,
      inquiryDate: inquiryDate ?? this.inquiryDate,
      customerName: customerName ?? this.customerName,
      customerAddress: customerAddress ?? this.customerAddress,
      customerEmail: customerEmail ?? this.customerEmail,
      customerPhone: customerPhone ?? this.customerPhone,
      senderEmail: senderEmail ?? this.senderEmail,
      items: items ?? this.items,
      notes: notes ?? this.notes,
      pdfPath: pdfPath ?? this.pdfPath,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      quotationId: quotationId ?? this.quotationId,
      poId: poId ?? this.poId,
    );
  }

  @override
  List<Object?> get props => [
        id,
        inquiryNumber,
        inquiryDate,
        customerName,
        customerAddress,
        customerEmail,
        customerPhone,
        senderEmail,
        items,
        notes,
        pdfPath,
        status,
        createdAt,
        updatedAt,
        quotationId,
        poId,
      ];
}

class InquiryItem extends Equatable {
  final String? id;
  final String itemName;
  final String? itemCode; // Material code
  final String? description;
  final double quantity;
  final String unit;
  final String? manufacturerPart;
  final String? classCode;
  final String? plant;
  /// Item-level status: 'pending' (no price / not quoted) or 'quoted' (price assigned and sent).
  final String status;

  const InquiryItem({
    this.id,
    required this.itemName,
    this.itemCode,
    this.description,
    required this.quantity,
    this.unit = 'EA',
    this.manufacturerPart,
    this.classCode,
    this.plant,
    this.status = 'pending',
  });

  InquiryItem copyWith({
    String? id,
    String? itemName,
    String? itemCode,
    String? description,
    double? quantity,
    String? unit,
    String? manufacturerPart,
    String? classCode,
    String? plant,
    String? status,
  }) {
    return InquiryItem(
      id: id ?? this.id,
      itemName: itemName ?? this.itemName,
      itemCode: itemCode ?? this.itemCode,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      manufacturerPart: manufacturerPart ?? this.manufacturerPart,
      classCode: classCode ?? this.classCode,
      plant: plant ?? this.plant,
      status: status ?? this.status,
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
        manufacturerPart,
        classCode,
        plant,
        status,
      ];
}

