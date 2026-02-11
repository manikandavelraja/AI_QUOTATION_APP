import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/purchase_order.dart';
import '../../domain/entities/customer_inquiry.dart';
import '../../domain/entities/quotation.dart';
import '../../domain/entities/supplier_order.dart';
import '../../domain/entities/delivery_document.dart';
import '../../core/security/encryption_service.dart';
import '../../core/constants/app_constants.dart';

class WebStorageService {
  static SharedPreferences? _prefs;
  static final WebStorageService instance = WebStorageService._internal();

  WebStorageService._internal();

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _initializeDefaultUser();
  }

  Future<void> _initializeDefaultUser() async {
    final users = await getAllUsers();
    if (users.isEmpty) {
      final defaultPasswordHash = EncryptionService.hashPassword(AppConstants.defaultPassword);
      await _prefs!.setString('users', json.encode([
        {
          'id': 'default_user',
          'username': AppConstants.defaultUsername,
          'password_hash': defaultPasswordHash,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        }
      ]));
    }
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final usersJson = _prefs!.getString('users') ?? '[]';
    return List<Map<String, dynamic>>.from(json.decode(usersJson));
  }

  Future<bool> validateUser(String username, String password) async {
    final users = await getAllUsers();
    final user = users.firstWhere(
      (u) => u['username'] == username,
      orElse: () => {},
    );
    
    if (user.isEmpty) return false;
    
    final passwordHash = user['password_hash'] as String;
    return EncryptionService.verifyPassword(password, passwordHash);
  }

  Future<String> insertPurchaseOrder(PurchaseOrder po) async {
    await init();
    final id = po.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    final posJson = _prefs!.getString('purchase_orders') ?? '[]';
    final pos = List<Map<String, dynamic>>.from(json.decode(posJson));
    
    pos.add({
      'id': id,
      'po_number': po.poNumber,
      'po_date': po.poDate.millisecondsSinceEpoch,
      'expiry_date': po.expiryDate.millisecondsSinceEpoch,
      'customer_name': po.customerName,
      'customer_address': po.customerAddress,
      'customer_email': po.customerEmail,
      'total_amount': po.totalAmount,
      'currency': po.currency,
      'terms': po.terms,
      'notes': po.notes,
      'pdf_path': po.pdfPath,
      'status': po.status,
      'created_at': po.createdAt.millisecondsSinceEpoch,
      'updated_at': po.updatedAt?.millisecondsSinceEpoch,
      'quotation_reference': po.quotationReference,
      'line_items': po.lineItems.map((item) => {
        'id': item.id ?? '${id}_${po.lineItems.indexOf(item)}',
        'item_name': item.itemName,
        'item_code': item.itemCode,
        'description': item.description,
        'quantity': item.quantity,
        'unit': item.unit,
        'unit_price': item.unitPrice,
        'total': item.total,
      }).toList(),
    });
    
    await _prefs!.setString('purchase_orders', json.encode(pos));
    return id;
  }

  Future<List<PurchaseOrder>> getAllPurchaseOrders() async {
    await init();
    final posJson = _prefs!.getString('purchase_orders') ?? '[]';
    final pos = List<Map<String, dynamic>>.from(json.decode(posJson));
    
    return pos.map((poMap) {
      final lineItems = (poMap['line_items'] as List<dynamic>?)
          ?.map((item) => LineItem(
                id: item['id'] as String?,
                itemName: item['item_name'] as String,
                itemCode: item['item_code'] as String?,
                description: item['description'] as String?,
                quantity: (item['quantity'] ?? 0).toDouble(),
                unit: item['unit'] as String? ?? 'pcs',
                unitPrice: (item['unit_price'] ?? 0).toDouble(),
                total: (item['total'] ?? 0).toDouble(),
              ))
          .toList() ?? [];
      
      String status = poMap['status'] as String? ?? 'active';
      final expiryDate = DateTime.fromMillisecondsSinceEpoch(poMap['expiry_date'] as int);
      if (expiryDate.isBefore(DateTime.now())) {
        status = 'expired';
      } else if (expiryDate.difference(DateTime.now()).inDays <= 7) {
        status = 'expiring_soon';
      }
      
      return PurchaseOrder(
        id: poMap['id'] as String,
        poNumber: poMap['po_number'] as String,
        poDate: DateTime.fromMillisecondsSinceEpoch(poMap['po_date'] as int),
        expiryDate: expiryDate,
        customerName: poMap['customer_name'] as String,
        customerAddress: poMap['customer_address'] as String?,
        customerEmail: poMap['customer_email'] as String?,
        totalAmount: (poMap['total_amount'] ?? 0).toDouble(),
        currency: poMap['currency'] as String?,
        terms: poMap['terms'] as String?,
        notes: poMap['notes'] as String?,
        pdfPath: poMap['pdf_path'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(poMap['created_at'] as int),
        updatedAt: poMap['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(poMap['updated_at'] as int)
            : null,
        status: status,
        quotationReference: poMap['quotation_reference'] as String?,
        lineItems: lineItems,
      );
    }).toList();
  }

  Future<PurchaseOrder?> getPurchaseOrderById(String id) async {
    final allPOs = await getAllPurchaseOrders();
    try {
      return allPOs.firstWhere((po) => po.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<void> updatePurchaseOrder(PurchaseOrder po) async {
    await init();
    final posJson = _prefs!.getString('purchase_orders') ?? '[]';
    final pos = List<Map<String, dynamic>>.from(json.decode(posJson));
    
    final index = pos.indexWhere((p) => p['id'] == po.id);
    if (index != -1) {
      pos[index] = {
        'id': po.id,
        'po_number': po.poNumber,
        'po_date': po.poDate.millisecondsSinceEpoch,
        'expiry_date': po.expiryDate.millisecondsSinceEpoch,
        'customer_name': po.customerName,
        'customer_address': po.customerAddress,
        'customer_email': po.customerEmail,
        'total_amount': po.totalAmount,
        'currency': po.currency,
        'terms': po.terms,
        'notes': po.notes,
        'pdf_path': po.pdfPath,
        'status': po.status,
        'created_at': pos[index]['created_at'],
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'quotation_reference': po.quotationReference,
        'line_items': po.lineItems.map((item) => {
          'id': item.id ?? '${po.id}_${po.lineItems.indexOf(item)}',
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'unit_price': item.unitPrice,
          'total': item.total,
        }).toList(),
      };
      
      await _prefs!.setString('purchase_orders', json.encode(pos));
    }
  }

  Future<void> deletePurchaseOrder(String id) async {
    await init();
    final posJson = _prefs!.getString('purchase_orders') ?? '[]';
    final pos = List<Map<String, dynamic>>.from(json.decode(posJson));
    pos.removeWhere((p) => p['id'] == id);
    await _prefs!.setString('purchase_orders', json.encode(pos));
  }

  Future<Map<String, dynamic>> getDashboardStats() async {
    final allPOs = await getAllPurchaseOrders();
    
    final now = DateTime.now();
    final weekFromNow = now.add(const Duration(days: 7));
    
    final todayPOs = allPOs.where((po) {
      return po.poDate.year == now.year &&
          po.poDate.month == now.month &&
          po.poDate.day == now.day;
    }).toList();
    
    final expiringThisWeek = allPOs.where((po) {
      return po.expiryDate.isAfter(now) && po.expiryDate.isBefore(weekFromNow);
    }).toList();
    
    final totalValue = allPOs.fold<double>(0, (sum, po) => sum + po.totalAmount);
    final todayValue = todayPOs.fold<double>(0, (sum, po) => sum + po.totalAmount);
    
    return {
      'totalPOs': allPOs.length,
      'todayPOs': todayPOs.length,
      'totalValue': totalValue,
      'todayValue': todayValue,
      'expiringThisWeek': expiringThisWeek.length,
      'expiringPOs': expiringThisWeek,
    };
  }

  // ========== CUSTOMER INQUIRIES ==========
  Future<String> insertCustomerInquiry(CustomerInquiry inquiry) async {
    await init();
    final id = inquiry.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    final inquiriesJson = _prefs!.getString('customer_inquiries') ?? '[]';
    final inquiries = List<Map<String, dynamic>>.from(json.decode(inquiriesJson));
    
    inquiries.add({
      'id': id,
      'inquiry_number': inquiry.inquiryNumber,
      'inquiry_date': inquiry.inquiryDate.millisecondsSinceEpoch,
      'customer_name': inquiry.customerName,
      'customer_address': inquiry.customerAddress,
      'customer_email': inquiry.customerEmail,
      'customer_phone': inquiry.customerPhone,
      'sender_email': inquiry.senderEmail,
      'notes': inquiry.notes,
      'pdf_path': inquiry.pdfPath,
      'status': inquiry.status,
      'created_at': inquiry.createdAt.millisecondsSinceEpoch,
      'updated_at': inquiry.updatedAt?.millisecondsSinceEpoch,
      'quotation_id': inquiry.quotationId,
      'po_id': inquiry.poId,
      'items': inquiry.items.map((item) => {
        'id': item.id ?? '${id}_${inquiry.items.indexOf(item)}',
        'item_name': item.itemName,
        'item_code': item.itemCode,
        'description': item.description,
        'quantity': item.quantity,
        'unit': item.unit,
        'manufacturer_part': item.manufacturerPart,
        'class_code': item.classCode,
        'plant': item.plant,
      }).toList(),
    });
    
    await _prefs!.setString('customer_inquiries', json.encode(inquiries));
    return id;
  }

  Future<List<CustomerInquiry>> getAllCustomerInquiries() async {
    await init();
    final inquiriesJson = _prefs!.getString('customer_inquiries') ?? '[]';
    final inquiries = List<Map<String, dynamic>>.from(json.decode(inquiriesJson));
    
    return inquiries.map((inqMap) {
      final items = (inqMap['items'] as List<dynamic>?)
          ?.map((item) => InquiryItem(
                id: item['id'] as String?,
                itemName: item['item_name'] as String,
                itemCode: item['item_code'] as String?,
                description: item['description'] as String?,
                quantity: (item['quantity'] ?? 0).toDouble(),
                unit: item['unit'] as String? ?? 'EA',
                manufacturerPart: item['manufacturer_part'] as String?,
                classCode: item['class_code'] as String?,
                plant: item['plant'] as String?,
              ))
          .toList() ?? [];
      
      return CustomerInquiry(
        id: inqMap['id'] as String,
        inquiryNumber: inqMap['inquiry_number'] as String,
        inquiryDate: DateTime.fromMillisecondsSinceEpoch(inqMap['inquiry_date'] as int),
        customerName: inqMap['customer_name'] as String,
        customerAddress: inqMap['customer_address'] as String?,
        customerEmail: inqMap['customer_email'] as String?,
        customerPhone: inqMap['customer_phone'] as String?,
        senderEmail: inqMap['sender_email'] as String?,
        items: items,
        notes: inqMap['notes'] as String?,
        pdfPath: inqMap['pdf_path'] as String?,
        status: inqMap['status'] as String? ?? 'pending',
        createdAt: DateTime.fromMillisecondsSinceEpoch(inqMap['created_at'] as int),
        updatedAt: inqMap['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(inqMap['updated_at'] as int)
            : null,
        quotationId: inqMap['quotation_id'] as String?,
        poId: inqMap['po_id'] as String?,
      );
    }).toList();
  }

  Future<CustomerInquiry?> getCustomerInquiryById(String id) async {
    final allInquiries = await getAllCustomerInquiries();
    try {
      return allInquiries.firstWhere((inq) => inq.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<void> updateCustomerInquiry(CustomerInquiry inquiry) async {
    await init();
    final inquiriesJson = _prefs!.getString('customer_inquiries') ?? '[]';
    final inquiries = List<Map<String, dynamic>>.from(json.decode(inquiriesJson));
    
    final index = inquiries.indexWhere((i) => i['id'] == inquiry.id);
    if (index != -1) {
      inquiries[index] = {
        'id': inquiry.id,
        'inquiry_number': inquiry.inquiryNumber,
        'inquiry_date': inquiry.inquiryDate.millisecondsSinceEpoch,
        'customer_name': inquiry.customerName,
        'customer_address': inquiry.customerAddress,
        'customer_email': inquiry.customerEmail,
        'customer_phone': inquiry.customerPhone,
        'sender_email': inquiry.senderEmail,
        'notes': inquiry.notes,
        'pdf_path': inquiry.pdfPath,
        'status': inquiry.status,
        'created_at': inquiries[index]['created_at'],
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'quotation_id': inquiry.quotationId,
        'po_id': inquiry.poId,
        'items': inquiry.items.map((item) => {
          'id': item.id ?? '${inquiry.id}_${inquiry.items.indexOf(item)}',
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'manufacturer_part': item.manufacturerPart,
          'class_code': item.classCode,
          'plant': item.plant,
        }).toList(),
      };
      
      await _prefs!.setString('customer_inquiries', json.encode(inquiries));
    }
  }

  Future<void> deleteCustomerInquiry(String id) async {
    await init();
    final inquiriesJson = _prefs!.getString('customer_inquiries') ?? '[]';
    final inquiries = List<Map<String, dynamic>>.from(json.decode(inquiriesJson));
    inquiries.removeWhere((i) => i['id'] == id);
    await _prefs!.setString('customer_inquiries', json.encode(inquiries));
  }

  // ========== QUOTATIONS ==========
  Future<String> insertQuotation(Quotation quotation) async {
    await init();
    final id = quotation.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    final quotationsJson = _prefs!.getString('quotations') ?? '[]';
    final quotations = List<Map<String, dynamic>>.from(json.decode(quotationsJson));
    
    quotations.add({
      'id': id,
      'quotation_number': quotation.quotationNumber,
      'quotation_date': quotation.quotationDate.millisecondsSinceEpoch,
      'validity_date': quotation.validityDate.millisecondsSinceEpoch,
      'customer_name': quotation.customerName,
      'customer_address': quotation.customerAddress,
      'customer_email': quotation.customerEmail,
      'customer_phone': quotation.customerPhone,
      'total_amount': quotation.totalAmount,
      'currency': quotation.currency,
      'terms': quotation.terms,
      'notes': quotation.notes,
      'pdf_path': quotation.pdfPath,
      'status': quotation.status,
      'created_at': quotation.createdAt.millisecondsSinceEpoch,
      'updated_at': quotation.updatedAt?.millisecondsSinceEpoch,
      'inquiry_id': quotation.inquiryId,
      'po_id': quotation.poId,
      'items': quotation.items.map((item) => {
        'id': item.id ?? '${id}_${quotation.items.indexOf(item)}',
        'item_name': item.itemName,
        'item_code': item.itemCode,
        'description': item.description,
        'quantity': item.quantity,
        'unit': item.unit,
        'unit_price': item.unitPrice,
        'total': item.total,
        'manufacturer_part': item.manufacturerPart,
      }).toList(),
    });
    
    await _prefs!.setString('quotations', json.encode(quotations));
    return id;
  }

  Future<List<Quotation>> getAllQuotations() async {
    await init();
    final quotationsJson = _prefs!.getString('quotations') ?? '[]';
    final quotations = List<Map<String, dynamic>>.from(json.decode(quotationsJson));
    
    return quotations.map((qtnMap) {
      final items = (qtnMap['items'] as List<dynamic>?)
          ?.map((item) => QuotationItem(
                id: item['id'] as String?,
                itemName: item['item_name'] as String,
                itemCode: item['item_code'] as String?,
                description: item['description'] as String?,
                quantity: (item['quantity'] ?? 0).toDouble(),
                unit: item['unit'] as String? ?? 'EA',
                unitPrice: (item['unit_price'] ?? 0).toDouble(),
                total: (item['total'] ?? 0).toDouble(),
                manufacturerPart: item['manufacturer_part'] as String?,
              ))
          .toList() ?? [];
      
      String status = qtnMap['status'] as String? ?? 'draft';
      final validityDate = DateTime.fromMillisecondsSinceEpoch(qtnMap['validity_date'] as int);
      if (validityDate.isBefore(DateTime.now()) && status != 'accepted' && status != 'rejected') {
        status = 'expired';
      }
      
      return Quotation(
        id: qtnMap['id'] as String,
        quotationNumber: qtnMap['quotation_number'] as String,
        quotationDate: DateTime.fromMillisecondsSinceEpoch(qtnMap['quotation_date'] as int),
        validityDate: validityDate,
        customerName: qtnMap['customer_name'] as String,
        customerAddress: qtnMap['customer_address'] as String?,
        customerEmail: qtnMap['customer_email'] as String?,
        customerPhone: qtnMap['customer_phone'] as String?,
        items: items,
        totalAmount: (qtnMap['total_amount'] ?? 0).toDouble(),
        currency: qtnMap['currency'] as String?,
        terms: qtnMap['terms'] as String?,
        notes: qtnMap['notes'] as String?,
        pdfPath: qtnMap['pdf_path'] as String?,
        status: status,
        createdAt: DateTime.fromMillisecondsSinceEpoch(qtnMap['created_at'] as int),
        updatedAt: qtnMap['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(qtnMap['updated_at'] as int)
            : null,
        inquiryId: qtnMap['inquiry_id'] as String?,
        poId: qtnMap['po_id'] as String?,
      );
    }).toList();
  }

  Future<Quotation?> getQuotationById(String id) async {
    final allQuotations = await getAllQuotations();
    try {
      return allQuotations.firstWhere((qtn) => qtn.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<void> updateQuotation(Quotation quotation) async {
    await init();
    final quotationsJson = _prefs!.getString('quotations') ?? '[]';
    final quotations = List<Map<String, dynamic>>.from(json.decode(quotationsJson));
    
    final index = quotations.indexWhere((q) => q['id'] == quotation.id);
    if (index != -1) {
      quotations[index] = {
        'id': quotation.id,
        'quotation_number': quotation.quotationNumber,
        'quotation_date': quotation.quotationDate.millisecondsSinceEpoch,
        'validity_date': quotation.validityDate.millisecondsSinceEpoch,
        'customer_name': quotation.customerName,
        'customer_address': quotation.customerAddress,
        'customer_email': quotation.customerEmail,
        'customer_phone': quotation.customerPhone,
        'total_amount': quotation.totalAmount,
        'currency': quotation.currency,
        'terms': quotation.terms,
        'notes': quotation.notes,
        'pdf_path': quotation.pdfPath,
        'status': quotation.status,
        'created_at': quotations[index]['created_at'],
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'inquiry_id': quotation.inquiryId,
        'po_id': quotation.poId,
        'items': quotation.items.map((item) => {
          'id': item.id ?? '${quotation.id}_${quotation.items.indexOf(item)}',
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'unit_price': item.unitPrice,
          'total': item.total,
          'manufacturer_part': item.manufacturerPart,
        }).toList(),
      };
      
      await _prefs!.setString('quotations', json.encode(quotations));
    }
  }

  Future<void> deleteQuotation(String id) async {
    await init();
    final quotationsJson = _prefs!.getString('quotations') ?? '[]';
    final quotations = List<Map<String, dynamic>>.from(json.decode(quotationsJson));
    quotations.removeWhere((q) => q['id'] == id);
    await _prefs!.setString('quotations', json.encode(quotations));
  }

  // ========== SUPPLIER ORDERS ==========
  Future<String> insertSupplierOrder(SupplierOrder order) async {
    await init();
    final id = order.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    final ordersJson = _prefs!.getString('supplier_orders') ?? '[]';
    final orders = List<Map<String, dynamic>>.from(json.decode(ordersJson));
    
    orders.add({
      'id': id,
      'order_number': order.orderNumber,
      'order_date': order.orderDate.millisecondsSinceEpoch,
      'expected_delivery_date': order.expectedDeliveryDate?.millisecondsSinceEpoch,
      'supplier_name': order.supplierName,
      'supplier_address': order.supplierAddress,
      'supplier_email': order.supplierEmail,
      'supplier_phone': order.supplierPhone,
      'total_amount': order.totalAmount,
      'currency': order.currency,
      'terms': order.terms,
      'notes': order.notes,
      'status': order.status,
      'created_at': order.createdAt.millisecondsSinceEpoch,
      'updated_at': order.updatedAt?.millisecondsSinceEpoch,
      'po_id': order.poId,
      'delivery_document_id': order.deliveryDocumentId,
      'items': order.items.map((item) => {
        'id': item.id ?? '${id}_${order.items.indexOf(item)}',
        'item_name': item.itemName,
        'item_code': item.itemCode,
        'description': item.description,
        'quantity': item.quantity,
        'unit': item.unit,
        'unit_price': item.unitPrice,
        'total': item.total,
      }).toList(),
    });
    
    await _prefs!.setString('supplier_orders', json.encode(orders));
    return id;
  }

  Future<List<SupplierOrder>> getAllSupplierOrders() async {
    await init();
    final ordersJson = _prefs!.getString('supplier_orders') ?? '[]';
    final orders = List<Map<String, dynamic>>.from(json.decode(ordersJson));
    
    return orders.map((orderMap) {
      final items = (orderMap['items'] as List<dynamic>?)
          ?.map((item) => SupplierOrderItem(
                id: item['id'] as String?,
                itemName: item['item_name'] as String,
                itemCode: item['item_code'] as String?,
                description: item['description'] as String?,
                quantity: (item['quantity'] ?? 0).toDouble(),
                unit: item['unit'] as String? ?? 'EA',
                unitPrice: (item['unit_price'] ?? 0).toDouble(),
                total: (item['total'] ?? 0).toDouble(),
              ))
          .toList() ?? [];
      
      return SupplierOrder(
        id: orderMap['id'] as String,
        orderNumber: orderMap['order_number'] as String,
        orderDate: DateTime.fromMillisecondsSinceEpoch(orderMap['order_date'] as int),
        expectedDeliveryDate: orderMap['expected_delivery_date'] != null
            ? DateTime.fromMillisecondsSinceEpoch(orderMap['expected_delivery_date'] as int)
            : null,
        supplierName: orderMap['supplier_name'] as String,
        supplierAddress: orderMap['supplier_address'] as String?,
        supplierEmail: orderMap['supplier_email'] as String?,
        supplierPhone: orderMap['supplier_phone'] as String?,
        items: items,
        totalAmount: (orderMap['total_amount'] ?? 0).toDouble(),
        currency: orderMap['currency'] as String?,
        terms: orderMap['terms'] as String?,
        notes: orderMap['notes'] as String?,
        status: orderMap['status'] as String? ?? 'pending',
        createdAt: DateTime.fromMillisecondsSinceEpoch(orderMap['created_at'] as int),
        updatedAt: orderMap['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(orderMap['updated_at'] as int)
            : null,
        poId: orderMap['po_id'] as String?,
        deliveryDocumentId: orderMap['delivery_document_id'] as String?,
      );
    }).toList();
  }

  Future<SupplierOrder?> getSupplierOrderById(String id) async {
    final allOrders = await getAllSupplierOrders();
    try {
      return allOrders.firstWhere((order) => order.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<void> updateSupplierOrder(SupplierOrder order) async {
    await init();
    final ordersJson = _prefs!.getString('supplier_orders') ?? '[]';
    final orders = List<Map<String, dynamic>>.from(json.decode(ordersJson));
    
    final index = orders.indexWhere((o) => o['id'] == order.id);
    if (index != -1) {
      orders[index] = {
        'id': order.id,
        'order_number': order.orderNumber,
        'order_date': order.orderDate.millisecondsSinceEpoch,
        'expected_delivery_date': order.expectedDeliveryDate?.millisecondsSinceEpoch,
        'supplier_name': order.supplierName,
        'supplier_address': order.supplierAddress,
        'supplier_email': order.supplierEmail,
        'supplier_phone': order.supplierPhone,
        'total_amount': order.totalAmount,
        'currency': order.currency,
        'terms': order.terms,
        'notes': order.notes,
        'status': order.status,
        'created_at': orders[index]['created_at'],
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'po_id': order.poId,
        'delivery_document_id': order.deliveryDocumentId,
        'items': order.items.map((item) => {
          'id': item.id ?? '${order.id}_${order.items.indexOf(item)}',
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'unit_price': item.unitPrice,
          'total': item.total,
        }).toList(),
      };
      
      await _prefs!.setString('supplier_orders', json.encode(orders));
    }
  }

  Future<void> deleteSupplierOrder(String id) async {
    await init();
    final ordersJson = _prefs!.getString('supplier_orders') ?? '[]';
    final orders = List<Map<String, dynamic>>.from(json.decode(ordersJson));
    orders.removeWhere((o) => o['id'] == id);
    await _prefs!.setString('supplier_orders', json.encode(orders));
  }

  // ========== DELIVERY DOCUMENTS ==========
  Future<String> insertDeliveryDocument(DeliveryDocument document) async {
    await init();
    final id = document.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    final documentsJson = _prefs!.getString('delivery_documents') ?? '[]';
    final documents = List<Map<String, dynamic>>.from(json.decode(documentsJson));
    
    documents.add({
      'id': id,
      'document_number': document.documentNumber,
      'document_type': document.documentType,
      'document_date': document.documentDate.millisecondsSinceEpoch,
      'customer_name': document.customerName,
      'customer_address': document.customerAddress,
      'customer_email': document.customerEmail,
      'customer_phone': document.customerPhone,
      'customer_trn': document.customerTRN,
      'subtotal': document.subtotal,
      'vat_amount': document.vatAmount,
      'total_amount': document.totalAmount,
      'currency': document.currency,
      'terms': document.terms,
      'notes': document.notes,
      'pdf_path': document.pdfPath,
      'status': document.status,
      'created_at': document.createdAt.millisecondsSinceEpoch,
      'updated_at': document.updatedAt?.millisecondsSinceEpoch,
      'po_id': document.poId,
      'supplier_order_id': document.supplierOrderId,
      'items': document.items.map((item) => {
        'id': item.id ?? '${id}_${document.items.indexOf(item)}',
        'item_name': item.itemName,
        'item_code': item.itemCode,
        'description': item.description,
        'quantity': item.quantity,
        'unit': item.unit,
        'unit_price': item.unitPrice,
        'total': item.total,
      }).toList(),
    });
    
    await _prefs!.setString('delivery_documents', json.encode(documents));
    return id;
  }

  Future<List<DeliveryDocument>> getAllDeliveryDocuments() async {
    await init();
    final documentsJson = _prefs!.getString('delivery_documents') ?? '[]';
    final documents = List<Map<String, dynamic>>.from(json.decode(documentsJson));
    
    return documents.map((docMap) {
      final items = (docMap['items'] as List<dynamic>?)
          ?.map((item) => DeliveryItem(
                id: item['id'] as String?,
                itemName: item['item_name'] as String,
                itemCode: item['item_code'] as String?,
                description: item['description'] as String?,
                quantity: (item['quantity'] ?? 0).toDouble(),
                unit: item['unit'] as String? ?? 'EA',
                unitPrice: (item['unit_price'] ?? 0).toDouble(),
                total: (item['total'] ?? 0).toDouble(),
              ))
          .toList() ?? [];
      
      return DeliveryDocument(
        id: docMap['id'] as String,
        documentNumber: docMap['document_number'] as String,
        documentType: docMap['document_type'] as String,
        documentDate: DateTime.fromMillisecondsSinceEpoch(docMap['document_date'] as int),
        customerName: docMap['customer_name'] as String,
        customerAddress: docMap['customer_address'] as String?,
        customerEmail: docMap['customer_email'] as String?,
        customerPhone: docMap['customer_phone'] as String?,
        customerTRN: docMap['customer_trn'] as String?,
        items: items,
        subtotal: (docMap['subtotal'] ?? 0).toDouble(),
        vatAmount: docMap['vat_amount'] != null ? (docMap['vat_amount'] as num).toDouble() : null,
        totalAmount: (docMap['total_amount'] ?? 0).toDouble(),
        currency: docMap['currency'] as String?,
        terms: docMap['terms'] as String?,
        notes: docMap['notes'] as String?,
        pdfPath: docMap['pdf_path'] as String?,
        status: docMap['status'] as String? ?? 'draft',
        createdAt: DateTime.fromMillisecondsSinceEpoch(docMap['created_at'] as int),
        updatedAt: docMap['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(docMap['updated_at'] as int)
            : null,
        poId: docMap['po_id'] as String?,
        supplierOrderId: docMap['supplier_order_id'] as String?,
      );
    }).toList();
  }

  Future<DeliveryDocument?> getDeliveryDocumentById(String id) async {
    final allDocuments = await getAllDeliveryDocuments();
    try {
      return allDocuments.firstWhere((doc) => doc.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<void> updateDeliveryDocument(DeliveryDocument document) async {
    await init();
    final documentsJson = _prefs!.getString('delivery_documents') ?? '[]';
    final documents = List<Map<String, dynamic>>.from(json.decode(documentsJson));
    
    final index = documents.indexWhere((d) => d['id'] == document.id);
    if (index != -1) {
      documents[index] = {
        'id': document.id,
        'document_number': document.documentNumber,
        'document_type': document.documentType,
        'document_date': document.documentDate.millisecondsSinceEpoch,
        'customer_name': document.customerName,
        'customer_address': document.customerAddress,
        'customer_email': document.customerEmail,
        'customer_phone': document.customerPhone,
        'customer_trn': document.customerTRN,
        'subtotal': document.subtotal,
        'vat_amount': document.vatAmount,
        'total_amount': document.totalAmount,
        'currency': document.currency,
        'terms': document.terms,
        'notes': document.notes,
        'pdf_path': document.pdfPath,
        'status': document.status,
        'created_at': documents[index]['created_at'],
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'po_id': document.poId,
        'supplier_order_id': document.supplierOrderId,
        'items': document.items.map((item) => {
          'id': item.id ?? '${document.id}_${document.items.indexOf(item)}',
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'unit_price': item.unitPrice,
          'total': item.total,
        }).toList(),
      };
      
      await _prefs!.setString('delivery_documents', json.encode(documents));
    }
  }

  Future<void> deleteDeliveryDocument(String id) async {
    await init();
    final documentsJson = _prefs!.getString('delivery_documents') ?? '[]';
    final documents = List<Map<String, dynamic>>.from(json.decode(documentsJson));
    documents.removeWhere((d) => d['id'] == id);
    await _prefs!.setString('delivery_documents', json.encode(documents));
  }
}

