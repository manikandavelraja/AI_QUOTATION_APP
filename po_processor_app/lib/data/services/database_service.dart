import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/purchase_order.dart';
import '../../domain/entities/customer_inquiry.dart';
import '../../domain/entities/quotation.dart';
import '../../domain/entities/supplier_order.dart';
import '../../domain/entities/delivery_document.dart';
import '../../core/security/encryption_service.dart';
import 'web_storage_service.dart';

class DatabaseService {
  static Database? _database;
  static final DatabaseService instance = DatabaseService._internal();
  final WebStorageService _webStorage = WebStorageService.instance;

  DatabaseService._internal();

  Future<dynamic> get database async {
    if (kIsWeb) {
      await _webStorage.init();
      return _webStorage;
    }
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConstants.databaseName);

    return await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Users table
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // Purchase Orders table
    await db.execute('''
      CREATE TABLE purchase_orders (
        id TEXT PRIMARY KEY,
        po_number TEXT UNIQUE NOT NULL,
        po_date INTEGER NOT NULL,
        expiry_date INTEGER NOT NULL,
        customer_name TEXT NOT NULL,
        customer_address TEXT,
        customer_email TEXT,
        total_amount REAL NOT NULL,
        currency TEXT,
        terms TEXT,
        notes TEXT,
        pdf_path TEXT,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER,
        quotation_reference TEXT
      )
    ''');

    // Line Items table
    await db.execute('''
      CREATE TABLE line_items (
        id TEXT PRIMARY KEY,
        po_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        item_code TEXT,
        description TEXT,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        unit_price REAL NOT NULL,
        total REAL NOT NULL,
        FOREIGN KEY (po_id) REFERENCES purchase_orders (id) ON DELETE CASCADE
      )
    ''');

    // Create default user
    final defaultPasswordHash = EncryptionService.hashPassword(AppConstants.defaultPassword);
    await db.insert('users', {
      'id': 'default_user',
      'username': AppConstants.defaultUsername,
      'password_hash': defaultPasswordHash,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    // Create indexes
    await db.execute('CREATE INDEX idx_po_status ON purchase_orders(status)');
    await db.execute('CREATE INDEX idx_po_expiry ON purchase_orders(expiry_date)');
    await db.execute('CREATE INDEX idx_line_items_po ON line_items(po_id)');
    
    // Customer Inquiries table
    await db.execute('''
      CREATE TABLE customer_inquiries (
        id TEXT PRIMARY KEY,
        inquiry_number TEXT UNIQUE NOT NULL,
        inquiry_date INTEGER NOT NULL,
        customer_name TEXT NOT NULL,
        customer_address TEXT,
        customer_email TEXT,
        customer_phone TEXT,
        sender_email TEXT,
        notes TEXT,
        pdf_path TEXT,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER,
        quotation_id TEXT,
        po_id TEXT
      )
    ''');
    
    // Inquiry Items table
    await db.execute('''
      CREATE TABLE inquiry_items (
        id TEXT PRIMARY KEY,
        inquiry_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        item_code TEXT,
        description TEXT,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        manufacturer_part TEXT,
        class_code TEXT,
        plant TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (inquiry_id) REFERENCES customer_inquiries (id) ON DELETE CASCADE
      )
    ''');
    
    // Quotations table
    await db.execute('''
      CREATE TABLE quotations (
        id TEXT PRIMARY KEY,
        quotation_number TEXT UNIQUE NOT NULL,
        quotation_date INTEGER NOT NULL,
        validity_date INTEGER NOT NULL,
        customer_name TEXT NOT NULL,
        customer_address TEXT,
        customer_email TEXT,
        customer_phone TEXT,
        total_amount REAL NOT NULL,
        currency TEXT,
        terms TEXT,
        notes TEXT,
        pdf_path TEXT,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER,
        inquiry_id TEXT,
        po_id TEXT
      )
    ''');
    
    // Quotation Items table
    await db.execute('''
      CREATE TABLE quotation_items (
        id TEXT PRIMARY KEY,
        quotation_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        item_code TEXT,
        description TEXT,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        unit_price REAL NOT NULL,
        total REAL NOT NULL,
        manufacturer_part TEXT,
        FOREIGN KEY (quotation_id) REFERENCES quotations (id) ON DELETE CASCADE
      )
    ''');
    
    // Supplier Orders table
    await db.execute('''
      CREATE TABLE supplier_orders (
        id TEXT PRIMARY KEY,
        order_number TEXT UNIQUE NOT NULL,
        order_date INTEGER NOT NULL,
        expected_delivery_date INTEGER,
        supplier_name TEXT NOT NULL,
        supplier_address TEXT,
        supplier_email TEXT,
        supplier_phone TEXT,
        total_amount REAL NOT NULL,
        currency TEXT,
        terms TEXT,
        notes TEXT,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER,
        po_id TEXT,
        delivery_document_id TEXT
      )
    ''');
    
    // Supplier Order Items table
    await db.execute('''
      CREATE TABLE supplier_order_items (
        id TEXT PRIMARY KEY,
        supplier_order_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        item_code TEXT,
        description TEXT,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        unit_price REAL NOT NULL,
        total REAL NOT NULL,
        FOREIGN KEY (supplier_order_id) REFERENCES supplier_orders (id) ON DELETE CASCADE
      )
    ''');
    
    // Delivery Documents table
    await db.execute('''
      CREATE TABLE delivery_documents (
        id TEXT PRIMARY KEY,
        document_number TEXT UNIQUE NOT NULL,
        document_type TEXT NOT NULL,
        document_date INTEGER NOT NULL,
        customer_name TEXT NOT NULL,
        customer_address TEXT,
        customer_email TEXT,
        customer_phone TEXT,
        customer_trn TEXT,
        subtotal REAL NOT NULL,
        vat_amount REAL,
        total_amount REAL NOT NULL,
        currency TEXT,
        terms TEXT,
        notes TEXT,
        pdf_path TEXT,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER,
        po_id TEXT,
        supplier_order_id TEXT
      )
    ''');
    
    // Delivery Items table
    await db.execute('''
      CREATE TABLE delivery_items (
        id TEXT PRIMARY KEY,
        delivery_document_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        item_code TEXT,
        description TEXT,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        unit_price REAL NOT NULL,
        total REAL NOT NULL,
        FOREIGN KEY (delivery_document_id) REFERENCES delivery_documents (id) ON DELETE CASCADE
      )
    ''');
    
    // Create additional indexes
    await db.execute('CREATE INDEX idx_inquiry_status ON customer_inquiries(status)');
    await db.execute('CREATE INDEX idx_quotation_status ON quotations(status)');
    await db.execute('CREATE INDEX idx_quotation_validity ON quotations(validity_date)');
    await db.execute('CREATE INDEX idx_supplier_order_status ON supplier_orders(status)');
    await db.execute('CREATE INDEX idx_delivery_doc_type ON delivery_documents(document_type)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add currency column if it doesn't exist
      try {
        await db.execute('ALTER TABLE purchase_orders ADD COLUMN currency TEXT');
      } catch (e) {
        // Column might already exist, ignore error
      }
      
      // Add sender_email column to customer_inquiries if it doesn't exist
      try {
        await db.execute('ALTER TABLE customer_inquiries ADD COLUMN sender_email TEXT');
      } catch (e) {
        // Column might already exist, ignore error
      }
      
      // Create workflow tables for version 2
      // Customer Inquiries table
      try {
        await db.execute('''
          CREATE TABLE customer_inquiries (
            id TEXT PRIMARY KEY,
            inquiry_number TEXT UNIQUE NOT NULL,
            inquiry_date INTEGER NOT NULL,
            customer_name TEXT NOT NULL,
            customer_address TEXT,
            customer_email TEXT,
            customer_phone TEXT,
            sender_email TEXT,
            notes TEXT,
            pdf_path TEXT,
            status TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER,
            quotation_id TEXT,
            po_id TEXT
          )
        ''');
      } catch (e) {
        // Table might already exist
      }
      
      // Inquiry Items table
      try {
        await db.execute('''
          CREATE TABLE inquiry_items (
            id TEXT PRIMARY KEY,
            inquiry_id TEXT NOT NULL,
            item_name TEXT NOT NULL,
            item_code TEXT,
            description TEXT,
            quantity REAL NOT NULL,
            unit TEXT NOT NULL,
            manufacturer_part TEXT,
            class_code TEXT,
            plant TEXT,
            FOREIGN KEY (inquiry_id) REFERENCES customer_inquiries (id) ON DELETE CASCADE
          )
        ''');
      } catch (e) {
        // Table might already exist
      }
      
      // Quotations table
      try {
        await db.execute('''
          CREATE TABLE quotations (
            id TEXT PRIMARY KEY,
            quotation_number TEXT UNIQUE NOT NULL,
            quotation_date INTEGER NOT NULL,
            validity_date INTEGER NOT NULL,
            customer_name TEXT NOT NULL,
            customer_address TEXT,
            customer_email TEXT,
            customer_phone TEXT,
            total_amount REAL NOT NULL,
            currency TEXT,
            terms TEXT,
            notes TEXT,
            pdf_path TEXT,
            status TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER,
            inquiry_id TEXT,
            po_id TEXT
          )
        ''');
      } catch (e) {
        // Table might already exist
      }
      
      // Quotation Items table
      try {
        await db.execute('''
          CREATE TABLE quotation_items (
            id TEXT PRIMARY KEY,
            quotation_id TEXT NOT NULL,
            item_name TEXT NOT NULL,
            item_code TEXT,
            description TEXT,
            quantity REAL NOT NULL,
            unit TEXT NOT NULL,
            unit_price REAL NOT NULL,
            total REAL NOT NULL,
            manufacturer_part TEXT,
            is_priced INTEGER NOT NULL DEFAULT 1,
            status TEXT NOT NULL DEFAULT 'ready',
            FOREIGN KEY (quotation_id) REFERENCES quotations (id) ON DELETE CASCADE
          )
        ''');
      } catch (e) {
        // Table might already exist
      }
      
      // Supplier Orders table
      try {
        await db.execute('''
          CREATE TABLE supplier_orders (
            id TEXT PRIMARY KEY,
            order_number TEXT UNIQUE NOT NULL,
            order_date INTEGER NOT NULL,
            expected_delivery_date INTEGER,
            supplier_name TEXT NOT NULL,
            supplier_address TEXT,
            supplier_email TEXT,
            supplier_phone TEXT,
            total_amount REAL NOT NULL,
            currency TEXT,
            terms TEXT,
            notes TEXT,
            status TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER,
            po_id TEXT,
            delivery_document_id TEXT
          )
        ''');
      } catch (e) {
        // Table might already exist
      }
      
      // Supplier Order Items table
      try {
        await db.execute('''
          CREATE TABLE supplier_order_items (
            id TEXT PRIMARY KEY,
            supplier_order_id TEXT NOT NULL,
            item_name TEXT NOT NULL,
            item_code TEXT,
            description TEXT,
            quantity REAL NOT NULL,
            unit TEXT NOT NULL,
            unit_price REAL NOT NULL,
            total REAL NOT NULL,
            FOREIGN KEY (supplier_order_id) REFERENCES supplier_orders (id) ON DELETE CASCADE
          )
        ''');
      } catch (e) {
        // Table might already exist
      }
      
      // Delivery Documents table
      try {
        await db.execute('''
          CREATE TABLE delivery_documents (
            id TEXT PRIMARY KEY,
            document_number TEXT UNIQUE NOT NULL,
            document_type TEXT NOT NULL,
            document_date INTEGER NOT NULL,
            customer_name TEXT NOT NULL,
            customer_address TEXT,
            customer_email TEXT,
            customer_phone TEXT,
            customer_trn TEXT,
            subtotal REAL NOT NULL,
            vat_amount REAL,
            total_amount REAL NOT NULL,
            currency TEXT,
            terms TEXT,
            notes TEXT,
            pdf_path TEXT,
            status TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER,
            po_id TEXT,
            supplier_order_id TEXT
          )
        ''');
      } catch (e) {
        // Table might already exist
      }
      
      // Delivery Items table
      try {
        await db.execute('''
          CREATE TABLE delivery_items (
            id TEXT PRIMARY KEY,
            delivery_document_id TEXT NOT NULL,
            item_name TEXT NOT NULL,
            item_code TEXT,
            description TEXT,
            quantity REAL NOT NULL,
            unit TEXT NOT NULL,
            unit_price REAL NOT NULL,
            total REAL NOT NULL,
            FOREIGN KEY (delivery_document_id) REFERENCES delivery_documents (id) ON DELETE CASCADE
          )
        ''');
      } catch (e) {
        // Table might already exist
      }
      
      // Create additional indexes
      try {
        await db.execute('CREATE INDEX idx_inquiry_status ON customer_inquiries(status)');
        await db.execute('CREATE INDEX idx_quotation_status ON quotations(status)');
        await db.execute('CREATE INDEX idx_quotation_validity ON quotations(validity_date)');
        await db.execute('CREATE INDEX idx_supplier_order_status ON supplier_orders(status)');
        await db.execute('CREATE INDEX idx_delivery_doc_type ON delivery_documents(document_type)');
      } catch (e) {
        // Indexes might already exist
      }
      
      // Add sender_email column to customer_inquiries if it doesn't exist
      try {
        await db.execute('ALTER TABLE customer_inquiries ADD COLUMN sender_email TEXT');
      } catch (e) {
        // Column might already exist, ignore error
      }
    }
    
    // Migration for version 3: Ensure sender_email column exists
    if (oldVersion < 4) {
      // Add is_priced and status columns to quotation_items table
      try {
        await db.execute('ALTER TABLE quotation_items ADD COLUMN is_priced INTEGER NOT NULL DEFAULT 1');
      } catch (e) {
        // Column might already exist, ignore error
      }
      
      try {
        await db.execute('ALTER TABLE quotation_items ADD COLUMN status TEXT NOT NULL DEFAULT \'ready\'');
      } catch (e) {
        // Column might already exist, ignore error
      }
    }
    
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE customer_inquiries ADD COLUMN sender_email TEXT');
      } catch (e) {
        // Column might already exist, ignore error
      }
    }
    
    // Migration: Add quotation_reference column to purchase_orders table
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE purchase_orders ADD COLUMN quotation_reference TEXT');
        debugPrint('✅ Added quotation_reference column to purchase_orders table');
      } catch (e) {
        debugPrint('⚠️ quotation_reference column might already exist: $e');
      }
      try {
        await db.execute("ALTER TABLE inquiry_items ADD COLUMN status TEXT DEFAULT 'pending'");
        debugPrint('✅ Added status column to inquiry_items table');
      } catch (e) {
        debugPrint('⚠️ inquiry_items.status column might already exist: $e');
      }
    }
  }

  // Purchase Order operations
  Future<String> insertPurchaseOrder(PurchaseOrder po) async {
    if (kIsWeb) {
      return await _webStorage.insertPurchaseOrder(po);
    }
    final db = await database as Database;
    final id = po.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    await db.transaction((txn) async {
      await txn.insert('purchase_orders', {
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
      });

      for (final item in po.lineItems) {
        final itemId = item.id ?? '${id}_${po.lineItems.indexOf(item)}';
        await txn.insert('line_items', {
          'id': itemId,
          'po_id': id,
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'unit_price': item.unitPrice,
          'total': item.total,
        });
      }
    });

    return id;
  }

  Future<List<PurchaseOrder>> getAllPurchaseOrders() async {
    if (kIsWeb) {
      return await _webStorage.getAllPurchaseOrders();
    }
    final db = await database as Database;
    final poMaps = await db.query('purchase_orders', orderBy: 'created_at DESC');
    
    final List<PurchaseOrder> pos = [];
    for (final poMap in poMaps) {
      final lineItems = await db.query(
        'line_items',
        where: 'po_id = ?',
        whereArgs: [poMap['id']],
      );

      pos.add(PurchaseOrder(
        id: poMap['id'] as String,
        poNumber: poMap['po_number'] as String,
        poDate: DateTime.fromMillisecondsSinceEpoch(poMap['po_date'] as int),
        expiryDate: DateTime.fromMillisecondsSinceEpoch(poMap['expiry_date'] as int),
        customerName: poMap['customer_name'] as String,
        customerAddress: poMap['customer_address'] as String?,
        customerEmail: poMap['customer_email'] as String?,
        totalAmount: poMap['total_amount'] as double,
        currency: poMap['currency'] as String?,
        terms: poMap['terms'] as String?,
        notes: poMap['notes'] as String?,
        pdfPath: poMap['pdf_path'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(poMap['created_at'] as int),
        updatedAt: poMap['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(poMap['updated_at'] as int)
            : null,
        status: poMap['status'] as String,
        quotationReference: poMap['quotation_reference'] as String?,
        lineItems: lineItems.map((item) => LineItem(
              id: item['id'] as String?,
              itemName: item['item_name'] as String,
              itemCode: item['item_code'] as String?,
              description: item['description'] as String?,
              quantity: item['quantity'] as double,
              unit: item['unit'] as String,
              unitPrice: item['unit_price'] as double,
              total: item['total'] as double,
            )).toList(),
      ));
    }
    
    return pos;
  }

  Future<PurchaseOrder?> getPurchaseOrderById(String id) async {
    if (kIsWeb) {
      return await _webStorage.getPurchaseOrderById(id);
    }
    final db = await database as Database;
    final poMaps = await db.query(
      'purchase_orders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (poMaps.isEmpty) return null;

    final poMap = poMaps.first;
    final lineItems = await db.query(
      'line_items',
      where: 'po_id = ?',
      whereArgs: [id],
    );

    return PurchaseOrder(
      id: poMap['id'] as String,
      poNumber: poMap['po_number'] as String,
      poDate: DateTime.fromMillisecondsSinceEpoch(poMap['po_date'] as int),
      expiryDate: DateTime.fromMillisecondsSinceEpoch(poMap['expiry_date'] as int),
      customerName: poMap['customer_name'] as String,
      customerAddress: poMap['customer_address'] as String?,
      customerEmail: poMap['customer_email'] as String?,
        totalAmount: poMap['total_amount'] as double,
        currency: poMap['currency'] as String?,
        terms: poMap['terms'] as String?,
        notes: poMap['notes'] as String?,
        pdfPath: poMap['pdf_path'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(poMap['created_at'] as int),
      updatedAt: poMap['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(poMap['updated_at'] as int)
          : null,
      status: poMap['status'] as String,
      quotationReference: poMap['quotation_reference'] as String?,
      lineItems: lineItems.map((item) => LineItem(
            id: item['id'] as String?,
            itemName: item['item_name'] as String,
            itemCode: item['item_code'] as String?,
            description: item['description'] as String?,
            quantity: item['quantity'] as double,
            unit: item['unit'] as String,
            unitPrice: item['unit_price'] as double,
            total: item['total'] as double,
          )).toList(),
    );
  }

  Future<void> updatePurchaseOrder(PurchaseOrder po) async {
    if (kIsWeb) {
      return await _webStorage.updatePurchaseOrder(po);
    }
    final db = await database as Database;
    
    await db.transaction((txn) async {
      await txn.update(
        'purchase_orders',
        {
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
          'status': po.status,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'quotation_reference': po.quotationReference,
        },
        where: 'id = ?',
        whereArgs: [po.id],
      );

      // Delete old line items
      await txn.delete('line_items', where: 'po_id = ?', whereArgs: [po.id]);

      // Insert new line items
      for (final item in po.lineItems) {
        final itemId = item.id ?? '${po.id}_${po.lineItems.indexOf(item)}';
        await txn.insert('line_items', {
          'id': itemId,
          'po_id': po.id,
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'unit_price': item.unitPrice,
          'total': item.total,
        });
      }
    });
  }

  Future<void> deletePurchaseOrder(String id) async {
    if (kIsWeb) {
      return await _webStorage.deletePurchaseOrder(id);
    }
    final db = await database as Database;
    await db.delete('purchase_orders', where: 'id = ?', whereArgs: [id]);
  }

  // Authentication operations
  Future<bool> validateUser(String username, String password) async {
    if (kIsWeb) {
      return await _webStorage.validateUser(username, password);
    }
    final db = await database as Database;
    final users = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );

    if (users.isEmpty) return false;

    final passwordHash = users.first['password_hash'] as String;
    return EncryptionService.verifyPassword(password, passwordHash);
  }

  // Statistics
  Future<Map<String, dynamic>> getDashboardStats() async {
    if (kIsWeb) {
      return await _webStorage.getDashboardStats();
    }
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

  // ========== CUSTOMER INQUIRY OPERATIONS ==========
  Future<String> insertCustomerInquiry(CustomerInquiry inquiry) async {
    if (kIsWeb) {
      return await _webStorage.insertCustomerInquiry(inquiry);
    }
    final db = await database as Database;
    final id = inquiry.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    await db.transaction((txn) async {
      await txn.insert('customer_inquiries', {
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
      });

      for (final item in inquiry.items) {
        final itemId = item.id ?? '${id}_${inquiry.items.indexOf(item)}';
        await txn.insert('inquiry_items', {
          'id': itemId,
          'inquiry_id': id,
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'manufacturer_part': item.manufacturerPart,
          'class_code': item.classCode,
          'plant': item.plant,
          'status': item.status,
        });
      }
    });

    return id;
  }

  Future<List<CustomerInquiry>> getAllCustomerInquiries() async {
    if (kIsWeb) {
      return await _webStorage.getAllCustomerInquiries();
    }
    final db = await database as Database;
    final inquiryMaps = await db.query('customer_inquiries', orderBy: 'created_at DESC');
    
    final List<CustomerInquiry> inquiries = [];
    for (final inquiryMap in inquiryMaps) {
      final items = await db.query(
        'inquiry_items',
        where: 'inquiry_id = ?',
        whereArgs: [inquiryMap['id']],
      );

      inquiries.add(CustomerInquiry(
        id: inquiryMap['id'] as String,
        inquiryNumber: inquiryMap['inquiry_number'] as String,
        inquiryDate: DateTime.fromMillisecondsSinceEpoch(inquiryMap['inquiry_date'] as int),
        customerName: inquiryMap['customer_name'] as String,
        customerAddress: inquiryMap['customer_address'] as String?,
        customerEmail: inquiryMap['customer_email'] as String?,
        customerPhone: inquiryMap['customer_phone'] as String?,
        senderEmail: inquiryMap['sender_email'] as String?,
        notes: inquiryMap['notes'] as String?,
        pdfPath: inquiryMap['pdf_path'] as String?,
        status: inquiryMap['status'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(inquiryMap['created_at'] as int),
        updatedAt: inquiryMap['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(inquiryMap['updated_at'] as int)
            : null,
        quotationId: inquiryMap['quotation_id'] as String?,
        poId: inquiryMap['po_id'] as String?,
        items: items.map((item) => InquiryItem(
              id: item['id'] as String?,
              itemName: item['item_name'] as String,
              itemCode: item['item_code'] as String?,
              description: item['description'] as String?,
              quantity: item['quantity'] as double,
              unit: item['unit'] as String,
              manufacturerPart: item['manufacturer_part'] as String?,
              classCode: item['class_code'] as String?,
              plant: item['plant'] as String?,
              status: item['status'] as String? ?? 'pending',
            )).toList(),
      ));
    }
    
    return inquiries;
  }

  Future<CustomerInquiry?> getCustomerInquiryById(String id) async {
    if (kIsWeb) {
      return await _webStorage.getCustomerInquiryById(id);
    }
    final db = await database as Database;
    final inquiryMaps = await db.query(
      'customer_inquiries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (inquiryMaps.isEmpty) return null;

    final inquiryMap = inquiryMaps.first;
    final items = await db.query(
      'inquiry_items',
      where: 'inquiry_id = ?',
      whereArgs: [id],
    );

    return CustomerInquiry(
      id: inquiryMap['id'] as String,
      inquiryNumber: inquiryMap['inquiry_number'] as String,
      inquiryDate: DateTime.fromMillisecondsSinceEpoch(inquiryMap['inquiry_date'] as int),
      customerName: inquiryMap['customer_name'] as String,
      customerAddress: inquiryMap['customer_address'] as String?,
      customerEmail: inquiryMap['customer_email'] as String?,
      customerPhone: inquiryMap['customer_phone'] as String?,
      senderEmail: inquiryMap['sender_email'] as String?,
      notes: inquiryMap['notes'] as String?,
      pdfPath: inquiryMap['pdf_path'] as String?,
      status: inquiryMap['status'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(inquiryMap['created_at'] as int),
      updatedAt: inquiryMap['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(inquiryMap['updated_at'] as int)
          : null,
      quotationId: inquiryMap['quotation_id'] as String?,
      poId: inquiryMap['po_id'] as String?,
      items: items.map((item) => InquiryItem(
            id: item['id'] as String?,
            itemName: item['item_name'] as String,
            itemCode: item['item_code'] as String?,
            description: item['description'] as String?,
            quantity: item['quantity'] as double,
            unit: item['unit'] as String,
            manufacturerPart: item['manufacturer_part'] as String?,
            classCode: item['class_code'] as String?,
            plant: item['plant'] as String?,
            status: item['status'] as String? ?? 'pending',
          )).toList(),
    );
  }

  Future<void> updateCustomerInquiry(CustomerInquiry inquiry) async {
    if (kIsWeb) {
      return await _webStorage.updateCustomerInquiry(inquiry);
    }
    final db = await database as Database;
    
    await db.transaction((txn) async {
      await txn.update(
        'customer_inquiries',
        {
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
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'quotation_id': inquiry.quotationId,
          'po_id': inquiry.poId,
        },
        where: 'id = ?',
        whereArgs: [inquiry.id],
      );

      await txn.delete('inquiry_items', where: 'inquiry_id = ?', whereArgs: [inquiry.id]);

      for (final item in inquiry.items) {
        final itemId = item.id ?? '${inquiry.id}_${inquiry.items.indexOf(item)}';
        await txn.insert('inquiry_items', {
          'id': itemId,
          'inquiry_id': inquiry.id,
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'manufacturer_part': item.manufacturerPart,
          'class_code': item.classCode,
          'plant': item.plant,
          'status': item.status,
        });
      }
    });
  }

  Future<void> deleteCustomerInquiry(String id) async {
    if (kIsWeb) {
      return await _webStorage.deleteCustomerInquiry(id);
    }
    final db = await database as Database;
    await db.delete('customer_inquiries', where: 'id = ?', whereArgs: [id]);
  }

  // ========== QUOTATION OPERATIONS ==========
  Future<String> insertQuotation(Quotation quotation) async {
    if (kIsWeb) {
      return await _webStorage.insertQuotation(quotation);
    }
    final db = await database as Database;
    final id = quotation.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    await db.transaction((txn) async {
      await txn.insert('quotations', {
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
      });

      for (final item in quotation.items) {
        final itemId = item.id ?? '${id}_${quotation.items.indexOf(item)}';
        await txn.insert('quotation_items', {
          'id': itemId,
          'quotation_id': id,
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'unit_price': item.unitPrice,
          'total': item.total,
          'manufacturer_part': item.manufacturerPart,
          'is_priced': item.isPriced ? 1 : 0,
          'status': item.status,
        });
      }
    });

    return id;
  }

  Future<List<Quotation>> getAllQuotations() async {
    if (kIsWeb) {
      return await _webStorage.getAllQuotations();
    }
    final db = await database as Database;
    final quotationMaps = await db.query('quotations', orderBy: 'created_at DESC');
    
    final List<Quotation> quotations = [];
    for (final quotationMap in quotationMaps) {
      final items = await db.query(
        'quotation_items',
        where: 'quotation_id = ?',
        whereArgs: [quotationMap['id']],
      );

      quotations.add(Quotation(
        id: quotationMap['id'] as String,
        quotationNumber: quotationMap['quotation_number'] as String,
        quotationDate: DateTime.fromMillisecondsSinceEpoch(quotationMap['quotation_date'] as int),
        validityDate: DateTime.fromMillisecondsSinceEpoch(quotationMap['validity_date'] as int),
        customerName: quotationMap['customer_name'] as String,
        customerAddress: quotationMap['customer_address'] as String?,
        customerEmail: quotationMap['customer_email'] as String?,
        customerPhone: quotationMap['customer_phone'] as String?,
        totalAmount: quotationMap['total_amount'] as double,
        currency: quotationMap['currency'] as String?,
        terms: quotationMap['terms'] as String?,
        notes: quotationMap['notes'] as String?,
        pdfPath: quotationMap['pdf_path'] as String?,
        status: quotationMap['status'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(quotationMap['created_at'] as int),
        updatedAt: quotationMap['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(quotationMap['updated_at'] as int)
            : null,
        inquiryId: quotationMap['inquiry_id'] as String?,
        poId: quotationMap['po_id'] as String?,
        items: items.map((item) => QuotationItem(
              id: item['id'] as String?,
              itemName: item['item_name'] as String,
              itemCode: item['item_code'] as String?,
              description: item['description'] as String?,
              quantity: item['quantity'] as double,
              unit: item['unit'] as String,
              unitPrice: item['unit_price'] as double,
              total: item['total'] as double,
              manufacturerPart: item['manufacturer_part'] as String?,
              isPriced: (item['is_priced'] as int? ?? 1) == 1,
              status: item['status'] as String? ?? 'ready',
            )).toList(),
      ));
    }
    
    return quotations;
  }

  /// Get historical quotations for a specific material code and customer
  /// Returns the last 5 quotations matching the criteria
  Future<List<Quotation>> getHistoricalQuotationsByMaterialAndCustomer({
    required String materialCode,
    required String customerName,
    int limit = 5,
  }) async {
    if (kIsWeb) {
      final allQuotations = await _webStorage.getAllQuotations();
      final filtered = allQuotations.where((qtn) {
        final hasMaterial = qtn.items.any((item) => 
          item.itemCode?.toLowerCase() == materialCode.toLowerCase()
        );
        final matchesCustomer = qtn.customerName.toLowerCase() == customerName.toLowerCase();
        return hasMaterial && matchesCustomer;
      }).toList();
      
      // Sort by date descending and take last 5
      filtered.sort((a, b) => b.quotationDate.compareTo(a.quotationDate));
      return filtered.take(limit).toList();
    }
    
    final db = await database as Database;
    
    // Query quotations with matching customer name
    final quotationMaps = await db.query(
      'quotations',
      where: 'customer_name = ?',
      whereArgs: [customerName],
      orderBy: 'quotation_date DESC',
    );
    
    final List<Quotation> matchingQuotations = [];
    
    for (final quotationMap in quotationMaps) {
      // Get items for this quotation
      final items = await db.query(
        'quotation_items',
        where: 'quotation_id = ? AND item_code = ?',
        whereArgs: [quotationMap['id'], materialCode],
      );
      
      // If this quotation has the material code, include it
      if (items.isNotEmpty) {
        // Get all items for this quotation
        final allItems = await db.query(
          'quotation_items',
          where: 'quotation_id = ?',
          whereArgs: [quotationMap['id']],
        );
        
        matchingQuotations.add(Quotation(
          id: quotationMap['id'] as String,
          quotationNumber: quotationMap['quotation_number'] as String,
          quotationDate: DateTime.fromMillisecondsSinceEpoch(quotationMap['quotation_date'] as int),
          validityDate: DateTime.fromMillisecondsSinceEpoch(quotationMap['validity_date'] as int),
          customerName: quotationMap['customer_name'] as String,
          customerAddress: quotationMap['customer_address'] as String?,
          customerEmail: quotationMap['customer_email'] as String?,
          customerPhone: quotationMap['customer_phone'] as String?,
          totalAmount: quotationMap['total_amount'] as double,
          currency: quotationMap['currency'] as String?,
          terms: quotationMap['terms'] as String?,
          notes: quotationMap['notes'] as String?,
          pdfPath: quotationMap['pdf_path'] as String?,
          status: quotationMap['status'] as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(quotationMap['created_at'] as int),
          updatedAt: quotationMap['updated_at'] != null
              ? DateTime.fromMillisecondsSinceEpoch(quotationMap['updated_at'] as int)
              : null,
          inquiryId: quotationMap['inquiry_id'] as String?,
          poId: quotationMap['po_id'] as String?,
          items: allItems.map((item) => QuotationItem(
                id: item['id'] as String?,
                itemName: item['item_name'] as String,
                itemCode: item['item_code'] as String?,
                description: item['description'] as String?,
                quantity: item['quantity'] as double,
                unit: item['unit'] as String,
                unitPrice: item['unit_price'] as double,
                total: item['total'] as double,
                manufacturerPart: item['manufacturer_part'] as String?,
                isPriced: (item['is_priced'] as int? ?? 1) == 1,
                status: item['status'] as String? ?? 'ready',
              )).toList(),
        ));
        
        // Stop when we have enough
        if (matchingQuotations.length >= limit) {
          break;
        }
      }
    }
    
    return matchingQuotations;
  }

  /// Get historical quotations for a material code, optionally scoped to one customer.
  /// One Customer Inquiry → multiple Quotations → multiple POs; this returns past quotes for reuse.
  Future<List<Quotation>> getHistoricalQuotationsByMaterialCode({
    required String materialCode,
    String? customerName,
    int limit = 10,
  }) async {
    debugPrint('🔍 [getHistoricalQuotationsByMaterialCode] Material: $materialCode, customer: $customerName');
    
    if (kIsWeb) {
      final allQuotations = await _webStorage.getAllQuotations();
      var filtered = allQuotations.where((qtn) {
        final hasMaterial = qtn.items.any((item) => 
          item.itemCode?.toLowerCase() == materialCode.toLowerCase()
        );
        return hasMaterial;
      }).toList();
      if (customerName != null && customerName.isNotEmpty) {
        final cn = customerName.trim().toLowerCase();
        filtered = filtered.where((q) => (q.customerName).trim().toLowerCase().contains(cn)).toList();
      }
      filtered.sort((a, b) => b.quotationDate.compareTo(a.quotationDate));
      final result = filtered.take(limit).toList();
      debugPrint('✅ [getHistoricalQuotationsByMaterialCode] Found ${result.length} quotations');
      return result;
    }
    
    final db = await database as Database;
    
    // Query all quotations
    final quotationMaps = await db.query(
      'quotations',
      orderBy: 'quotation_date DESC',
    );
    
    final List<Quotation> matchingQuotations = [];
    
    // Normalize material code for comparison (trim and lowercase)
    final normalizedMaterialCode = materialCode.trim().toLowerCase();
    debugPrint('🔍 [getHistoricalQuotationsByMaterialCode] Normalized Material Code: "$normalizedMaterialCode"');
    
    for (final quotationMap in quotationMaps) {
      // Get all items for this quotation first
      final allItems = await db.query(
        'quotation_items',
        where: 'quotation_id = ?',
        whereArgs: [quotationMap['id']],
      );
      
      // Check if any item matches the material code (case-insensitive, trimmed)
      final matchingItems = allItems.where((item) {
        final itemCode = (item['item_code'] as String? ?? '').trim().toLowerCase();
        return itemCode == normalizedMaterialCode;
      }).toList();
      
      // If this quotation has the material code, include it (and optionally same customer)
      final qCustomer = (quotationMap['customer_name'] as String? ?? '').trim().toLowerCase();
      final customerMatch = customerName == null || customerName.isEmpty ||
          qCustomer.contains(customerName.trim().toLowerCase());
      if (matchingItems.isNotEmpty && customerMatch) {
        debugPrint('✅ [getHistoricalQuotationsByMaterialCode] Found matching item in quotation: ${quotationMap['quotation_number']}');
        
        matchingQuotations.add(Quotation(
          id: quotationMap['id'] as String,
          quotationNumber: quotationMap['quotation_number'] as String,
          quotationDate: DateTime.fromMillisecondsSinceEpoch(quotationMap['quotation_date'] as int),
          validityDate: DateTime.fromMillisecondsSinceEpoch(quotationMap['validity_date'] as int),
          customerName: quotationMap['customer_name'] as String,
          customerAddress: quotationMap['customer_address'] as String?,
          customerEmail: quotationMap['customer_email'] as String?,
          customerPhone: quotationMap['customer_phone'] as String?,
          totalAmount: quotationMap['total_amount'] as double,
          currency: quotationMap['currency'] as String?,
          terms: quotationMap['terms'] as String?,
          notes: quotationMap['notes'] as String?,
          pdfPath: quotationMap['pdf_path'] as String?,
          status: quotationMap['status'] as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(quotationMap['created_at'] as int),
          updatedAt: quotationMap['updated_at'] != null
              ? DateTime.fromMillisecondsSinceEpoch(quotationMap['updated_at'] as int)
              : null,
          inquiryId: quotationMap['inquiry_id'] as String?,
          poId: quotationMap['po_id'] as String?,
          items: allItems.map((item) => QuotationItem(
                id: item['id'] as String?,
                itemName: item['item_name'] as String,
                itemCode: item['item_code'] as String?,
                description: item['description'] as String?,
                quantity: item['quantity'] as double,
                unit: item['unit'] as String,
                unitPrice: item['unit_price'] as double,
                total: item['total'] as double,
                manufacturerPart: item['manufacturer_part'] as String?,
                isPriced: (item['is_priced'] as int? ?? 1) == 1,
                status: item['status'] as String? ?? 'ready',
              )).toList(),
        ));
        
        // Stop when we have enough
        if (matchingQuotations.length >= limit) {
          break;
        }
      }
    }
    
    debugPrint('✅ [getHistoricalQuotationsByMaterialCode] Returning ${matchingQuotations.length} quotations for Material Code: $materialCode');
    return matchingQuotations;
  }

  /// Get Purchase Orders linked to a quotation by quotation reference or quotation ID
  Future<List<PurchaseOrder>> getPurchaseOrdersByQuotation({
    String? quotationNumber,
    String? quotationId,
  }) async {
    debugPrint('🔍 [getPurchaseOrdersByQuotation] Checking POs for Quotation Number: $quotationNumber, Quotation ID: $quotationId');
    
    if (kIsWeb) {
      final allPOs = await _webStorage.getAllPurchaseOrders();
      final filtered = allPOs.where((po) {
        if (quotationNumber != null && po.quotationReference != null) {
          return po.quotationReference!.toLowerCase().contains(quotationNumber.toLowerCase());
        }
        return false;
      }).toList();
      
      debugPrint('✅ [getPurchaseOrdersByQuotation] Found ${filtered.length} POs for Quotation: $quotationNumber');
      return filtered;
    }
    
    final db = await database as Database;
    final List<PurchaseOrder> matchingPOs = [];
    
    // Query POs by quotation reference
    if (quotationNumber != null) {
      final poMaps = await db.query(
        'purchase_orders',
        where: 'quotation_reference LIKE ?',
        whereArgs: ['%$quotationNumber%'],
      );
      
      for (final poMap in poMaps) {
        final lineItems = await db.query(
          'line_items',
          where: 'po_id = ?',
          whereArgs: [poMap['id']],
        );
        
        matchingPOs.add(PurchaseOrder(
          id: poMap['id'] as String,
          poNumber: poMap['po_number'] as String,
          poDate: DateTime.fromMillisecondsSinceEpoch(poMap['po_date'] as int),
          expiryDate: DateTime.fromMillisecondsSinceEpoch(poMap['expiry_date'] as int),
          customerName: poMap['customer_name'] as String,
          customerAddress: poMap['customer_address'] as String?,
          customerEmail: poMap['customer_email'] as String?,
          totalAmount: poMap['total_amount'] as double,
          currency: poMap['currency'] as String?,
          terms: poMap['terms'] as String?,
          notes: poMap['notes'] as String?,
          pdfPath: poMap['pdf_path'] as String?,
          createdAt: DateTime.fromMillisecondsSinceEpoch(poMap['created_at'] as int),
          updatedAt: poMap['updated_at'] != null
              ? DateTime.fromMillisecondsSinceEpoch(poMap['updated_at'] as int)
              : null,
          status: poMap['status'] as String,
          quotationReference: poMap['quotation_reference'] as String?,
          lineItems: lineItems.map((item) => LineItem(
                id: item['id'] as String?,
                itemName: item['item_name'] as String,
                itemCode: item['item_code'] as String?,
                description: item['description'] as String?,
                quantity: item['quantity'] as double,
                unit: item['unit'] as String,
                unitPrice: item['unit_price'] as double,
                total: item['total'] as double,
              )).toList(),
        ));
      }
    }
    
    debugPrint('✅ [getPurchaseOrdersByQuotation] Returning ${matchingPOs.length} POs for Quotation: $quotationNumber');
    return matchingPOs;
  }

  Future<Quotation?> getQuotationById(String id) async {
    if (kIsWeb) {
      return await _webStorage.getQuotationById(id);
    }
    final db = await database as Database;
    final quotationMaps = await db.query(
      'quotations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (quotationMaps.isEmpty) return null;

    final quotationMap = quotationMaps.first;
    final items = await db.query(
      'quotation_items',
      where: 'quotation_id = ?',
      whereArgs: [id],
    );

    return Quotation(
      id: quotationMap['id'] as String,
      quotationNumber: quotationMap['quotation_number'] as String,
      quotationDate: DateTime.fromMillisecondsSinceEpoch(quotationMap['quotation_date'] as int),
      validityDate: DateTime.fromMillisecondsSinceEpoch(quotationMap['validity_date'] as int),
      customerName: quotationMap['customer_name'] as String,
      customerAddress: quotationMap['customer_address'] as String?,
      customerEmail: quotationMap['customer_email'] as String?,
      customerPhone: quotationMap['customer_phone'] as String?,
      totalAmount: quotationMap['total_amount'] as double,
      currency: quotationMap['currency'] as String?,
      terms: quotationMap['terms'] as String?,
      notes: quotationMap['notes'] as String?,
      pdfPath: quotationMap['pdf_path'] as String?,
      status: quotationMap['status'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(quotationMap['created_at'] as int),
      updatedAt: quotationMap['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(quotationMap['updated_at'] as int)
          : null,
      inquiryId: quotationMap['inquiry_id'] as String?,
      poId: quotationMap['po_id'] as String?,
      items: items.map((item) => QuotationItem(
            id: item['id'] as String?,
            itemName: item['item_name'] as String,
            itemCode: item['item_code'] as String?,
            description: item['description'] as String?,
            quantity: item['quantity'] as double,
            unit: item['unit'] as String,
            unitPrice: item['unit_price'] as double,
            total: item['total'] as double,
            manufacturerPart: item['manufacturer_part'] as String?,
          )).toList(),
    );
  }

  Future<void> updateQuotation(Quotation quotation) async {
    if (kIsWeb) {
      return await _webStorage.updateQuotation(quotation);
    }
    final db = await database as Database;
    
    await db.transaction((txn) async {
      await txn.update(
        'quotations',
        {
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
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'inquiry_id': quotation.inquiryId,
          'po_id': quotation.poId,
        },
        where: 'id = ?',
        whereArgs: [quotation.id],
      );

      await txn.delete('quotation_items', where: 'quotation_id = ?', whereArgs: [quotation.id]);

      for (final item in quotation.items) {
        final itemId = item.id ?? '${quotation.id}_${quotation.items.indexOf(item)}';
        await txn.insert('quotation_items', {
          'id': itemId,
          'quotation_id': quotation.id,
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'unit_price': item.unitPrice,
          'total': item.total,
          'manufacturer_part': item.manufacturerPart,
          'is_priced': item.isPriced ? 1 : 0,
          'status': item.status,
        });
      }
    });
  }

  Future<void> deleteQuotation(String id) async {
    if (kIsWeb) {
      return await _webStorage.deleteQuotation(id);
    }
    final db = await database as Database;
    await db.delete('quotations', where: 'id = ?', whereArgs: [id]);
  }

  // ========== SUPPLIER ORDER OPERATIONS ==========
  Future<String> insertSupplierOrder(SupplierOrder order) async {
    if (kIsWeb) {
      return await _webStorage.insertSupplierOrder(order);
    }
    final db = await database as Database;
    final id = order.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    await db.transaction((txn) async {
      await txn.insert('supplier_orders', {
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
      });

      for (final item in order.items) {
        final itemId = item.id ?? '${id}_${order.items.indexOf(item)}';
        await txn.insert('supplier_order_items', {
          'id': itemId,
          'supplier_order_id': id,
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'unit_price': item.unitPrice,
          'total': item.total,
        });
      }
    });

    return id;
  }

  Future<List<SupplierOrder>> getAllSupplierOrders() async {
    if (kIsWeb) {
      return await _webStorage.getAllSupplierOrders();
    }
    final db = await database as Database;
    final orderMaps = await db.query('supplier_orders', orderBy: 'created_at DESC');
    
    final List<SupplierOrder> orders = [];
    for (final orderMap in orderMaps) {
      final items = await db.query(
        'supplier_order_items',
        where: 'supplier_order_id = ?',
        whereArgs: [orderMap['id']],
      );

      orders.add(SupplierOrder(
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
        totalAmount: orderMap['total_amount'] as double,
        currency: orderMap['currency'] as String?,
        terms: orderMap['terms'] as String?,
        notes: orderMap['notes'] as String?,
        status: orderMap['status'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(orderMap['created_at'] as int),
        updatedAt: orderMap['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(orderMap['updated_at'] as int)
            : null,
        poId: orderMap['po_id'] as String?,
        deliveryDocumentId: orderMap['delivery_document_id'] as String?,
        items: items.map((item) => SupplierOrderItem(
              id: item['id'] as String?,
              itemName: item['item_name'] as String,
              itemCode: item['item_code'] as String?,
              description: item['description'] as String?,
              quantity: item['quantity'] as double,
              unit: item['unit'] as String,
              unitPrice: item['unit_price'] as double,
              total: item['total'] as double,
            )).toList(),
      ));
    }
    
    return orders;
  }

  Future<SupplierOrder?> getSupplierOrderById(String id) async {
    if (kIsWeb) {
      return await _webStorage.getSupplierOrderById(id);
    }
    final db = await database as Database;
    final orderMaps = await db.query(
      'supplier_orders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (orderMaps.isEmpty) return null;

    final orderMap = orderMaps.first;
    final items = await db.query(
      'supplier_order_items',
      where: 'supplier_order_id = ?',
      whereArgs: [id],
    );

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
      totalAmount: orderMap['total_amount'] as double,
      currency: orderMap['currency'] as String?,
      terms: orderMap['terms'] as String?,
      notes: orderMap['notes'] as String?,
      status: orderMap['status'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(orderMap['created_at'] as int),
      updatedAt: orderMap['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(orderMap['updated_at'] as int)
          : null,
      poId: orderMap['po_id'] as String?,
      deliveryDocumentId: orderMap['delivery_document_id'] as String?,
      items: items.map((item) => SupplierOrderItem(
            id: item['id'] as String?,
            itemName: item['item_name'] as String,
            itemCode: item['item_code'] as String?,
            description: item['description'] as String?,
            quantity: item['quantity'] as double,
            unit: item['unit'] as String,
            unitPrice: item['unit_price'] as double,
            total: item['total'] as double,
          )).toList(),
    );
  }

  Future<void> updateSupplierOrder(SupplierOrder order) async {
    if (kIsWeb) {
      return await _webStorage.updateSupplierOrder(order);
    }
    final db = await database as Database;
    
    await db.transaction((txn) async {
      await txn.update(
        'supplier_orders',
        {
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
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'po_id': order.poId,
          'delivery_document_id': order.deliveryDocumentId,
        },
        where: 'id = ?',
        whereArgs: [order.id],
      );

      await txn.delete('supplier_order_items', where: 'supplier_order_id = ?', whereArgs: [order.id]);

      for (final item in order.items) {
        final itemId = item.id ?? '${order.id}_${order.items.indexOf(item)}';
        await txn.insert('supplier_order_items', {
          'id': itemId,
          'supplier_order_id': order.id,
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'unit_price': item.unitPrice,
          'total': item.total,
        });
      }
    });
  }

  Future<void> deleteSupplierOrder(String id) async {
    if (kIsWeb) {
      return await _webStorage.deleteSupplierOrder(id);
    }
    final db = await database as Database;
    await db.delete('supplier_orders', where: 'id = ?', whereArgs: [id]);
  }

  // ========== DELIVERY DOCUMENT OPERATIONS ==========
  Future<String> insertDeliveryDocument(DeliveryDocument document) async {
    if (kIsWeb) {
      return await _webStorage.insertDeliveryDocument(document);
    }
    final db = await database as Database;
    final id = document.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    await db.transaction((txn) async {
      await txn.insert('delivery_documents', {
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
      });

      for (final item in document.items) {
        final itemId = item.id ?? '${id}_${document.items.indexOf(item)}';
        await txn.insert('delivery_items', {
          'id': itemId,
          'delivery_document_id': id,
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'unit_price': item.unitPrice,
          'total': item.total,
        });
      }
    });

    return id;
  }

  Future<List<DeliveryDocument>> getAllDeliveryDocuments() async {
    if (kIsWeb) {
      return await _webStorage.getAllDeliveryDocuments();
    }
    final db = await database as Database;
    final documentMaps = await db.query('delivery_documents', orderBy: 'created_at DESC');
    
    final List<DeliveryDocument> documents = [];
    for (final documentMap in documentMaps) {
      final items = await db.query(
        'delivery_items',
        where: 'delivery_document_id = ?',
        whereArgs: [documentMap['id']],
      );

      documents.add(DeliveryDocument(
        id: documentMap['id'] as String,
        documentNumber: documentMap['document_number'] as String,
        documentType: documentMap['document_type'] as String,
        documentDate: DateTime.fromMillisecondsSinceEpoch(documentMap['document_date'] as int),
        customerName: documentMap['customer_name'] as String,
        customerAddress: documentMap['customer_address'] as String?,
        customerEmail: documentMap['customer_email'] as String?,
        customerPhone: documentMap['customer_phone'] as String?,
        customerTRN: documentMap['customer_trn'] as String?,
        subtotal: documentMap['subtotal'] as double,
        vatAmount: documentMap['vat_amount'] as double?,
        totalAmount: documentMap['total_amount'] as double,
        currency: documentMap['currency'] as String?,
        terms: documentMap['terms'] as String?,
        notes: documentMap['notes'] as String?,
        pdfPath: documentMap['pdf_path'] as String?,
        status: documentMap['status'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(documentMap['created_at'] as int),
        updatedAt: documentMap['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(documentMap['updated_at'] as int)
            : null,
        poId: documentMap['po_id'] as String?,
        supplierOrderId: documentMap['supplier_order_id'] as String?,
        items: items.map((item) => DeliveryItem(
              id: item['id'] as String?,
              itemName: item['item_name'] as String,
              itemCode: item['item_code'] as String?,
              description: item['description'] as String?,
              quantity: item['quantity'] as double,
              unit: item['unit'] as String,
              unitPrice: item['unit_price'] as double,
              total: item['total'] as double,
            )).toList(),
      ));
    }
    
    return documents;
  }

  Future<DeliveryDocument?> getDeliveryDocumentById(String id) async {
    if (kIsWeb) {
      return await _webStorage.getDeliveryDocumentById(id);
    }
    final db = await database as Database;
    final documentMaps = await db.query(
      'delivery_documents',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (documentMaps.isEmpty) return null;

    final documentMap = documentMaps.first;
    final items = await db.query(
      'delivery_items',
      where: 'delivery_document_id = ?',
      whereArgs: [id],
    );

    return DeliveryDocument(
      id: documentMap['id'] as String,
      documentNumber: documentMap['document_number'] as String,
      documentType: documentMap['document_type'] as String,
      documentDate: DateTime.fromMillisecondsSinceEpoch(documentMap['document_date'] as int),
      customerName: documentMap['customer_name'] as String,
      customerAddress: documentMap['customer_address'] as String?,
      customerEmail: documentMap['customer_email'] as String?,
      customerPhone: documentMap['customer_phone'] as String?,
      customerTRN: documentMap['customer_trn'] as String?,
      subtotal: documentMap['subtotal'] as double,
      vatAmount: documentMap['vat_amount'] as double?,
      totalAmount: documentMap['total_amount'] as double,
      currency: documentMap['currency'] as String?,
      terms: documentMap['terms'] as String?,
      notes: documentMap['notes'] as String?,
      pdfPath: documentMap['pdf_path'] as String?,
      status: documentMap['status'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(documentMap['created_at'] as int),
      updatedAt: documentMap['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(documentMap['updated_at'] as int)
          : null,
      poId: documentMap['po_id'] as String?,
      supplierOrderId: documentMap['supplier_order_id'] as String?,
      items: items.map((item) => DeliveryItem(
            id: item['id'] as String?,
            itemName: item['item_name'] as String,
            itemCode: item['item_code'] as String?,
            description: item['description'] as String?,
            quantity: item['quantity'] as double,
            unit: item['unit'] as String,
            unitPrice: item['unit_price'] as double,
            total: item['total'] as double,
          )).toList(),
    );
  }

  Future<void> updateDeliveryDocument(DeliveryDocument document) async {
    if (kIsWeb) {
      return await _webStorage.updateDeliveryDocument(document);
    }
    final db = await database as Database;
    
    await db.transaction((txn) async {
      await txn.update(
        'delivery_documents',
        {
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
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'po_id': document.poId,
          'supplier_order_id': document.supplierOrderId,
        },
        where: 'id = ?',
        whereArgs: [document.id],
      );

      await txn.delete('delivery_items', where: 'delivery_document_id = ?', whereArgs: [document.id]);

      for (final item in document.items) {
        final itemId = item.id ?? '${document.id}_${document.items.indexOf(item)}';
        await txn.insert('delivery_items', {
          'id': itemId,
          'delivery_document_id': document.id,
          'item_name': item.itemName,
          'item_code': item.itemCode,
          'description': item.description,
          'quantity': item.quantity,
          'unit': item.unit,
          'unit_price': item.unitPrice,
          'total': item.total,
        });
      }
    });
  }

  Future<void> deleteDeliveryDocument(String id) async {
    if (kIsWeb) {
      return await _webStorage.deleteDeliveryDocument(id);
    }
    final db = await database as Database;
    await db.delete('delivery_documents', where: 'id = ?', whereArgs: [id]);
  }
}

