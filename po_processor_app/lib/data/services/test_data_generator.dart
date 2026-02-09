import 'package:flutter/foundation.dart' show debugPrint;
import '../../domain/entities/purchase_order.dart';
import 'database_service.dart';

class TestDataGenerator {
  final DatabaseService _databaseService = DatabaseService.instance;

  /// Generates test purchase orders for the specified materials
  /// Based on the test records provided:
  /// - 1069683 (Water Tap): 2 units | AED 22 | Interval: Monthly
  /// - 1069685 (Bearing): 3 units | AED 11 | Interval: 3 Months
  /// - 1069687 (Timing Belt): 8 units | AED 11 | Interval: 15 Days
  /// - 1069689 (Filter): 12 units | AED 06 | Interval: 4 Months
  /// - 1069680 (Lubricant): 20 units | AED 15 | Interval: 6 Months
  Future<void> generateTestPurchaseOrders() async {
    debugPrint('🧪 [Test Data Generator] Starting test data generation...');

    final now = DateTime.now();
    final testMaterials = [
      {
        'code': '1069683',
        'name': 'Water Tap',
        'quantity': 2.0,
        'unitPrice': 22.0,
        'unit': 'pcs',
        'intervalDays': 30, // Monthly
      },
      {
        'code': '1069685',
        'name': 'Bearing',
        'quantity': 3.0,
        'unitPrice': 11.0,
        'unit': 'pcs',
        'intervalDays': 90, // 3 Months
      },
      {
        'code': '1069687',
        'name': 'Timing Belt',
        'quantity': 8.0,
        'unitPrice': 11.0,
        'unit': 'pcs',
        'intervalDays': 15, // 15 Days
      },
      {
        'code': '1069689',
        'name': 'Filter',
        'quantity': 12.0,
        'unitPrice': 6.0,
        'unit': 'pcs',
        'intervalDays': 120, // 4 Months
      },
      {
        'code': '1069680',
        'name': 'Lubricant',
        'quantity': 20.0,
        'unitPrice': 15.0,
        'unit': 'pcs',
        'intervalDays': 180, // 6 Months
      },
    ];

    int poCounter = 1;
    final generatedPOs = <PurchaseOrder>[];

    // Generate POs for each material over the last 12 months
    for (final material in testMaterials) {
      final code = material['code'] as String;
      final name = material['name'] as String;
      final quantity = material['quantity'] as double;
      final unitPrice = material['unitPrice'] as double;
      final unit = material['unit'] as String;
      final intervalDays = material['intervalDays'] as int;

      debugPrint(
        '📦 Generating POs for $name (Code: $code, Interval: $intervalDays days)',
      );

      // Calculate how many purchases in last 12 months
      final monthsOfData = 12;
      final totalDays = monthsOfData * 30;
      final numberOfPurchases = (totalDays / intervalDays).ceil();

      // Start from 12 months ago and generate purchases at intervals
      var purchaseDate = DateTime(now.year - 1, now.month, now.day);

      for (int i = 0; i < numberOfPurchases; i++) {
        // Skip if date is in the future
        if (purchaseDate.isAfter(now)) {
          break;
        }

        final totalAmount = quantity * unitPrice;
        final expiryDate = purchaseDate.add(
          Duration(days: intervalDays + 30),
        ); // Add buffer for expiry

        final po = PurchaseOrder(
          poNumber: 'TEST-PO-${poCounter.toString().padLeft(4, '0')}',
          poDate: purchaseDate,
          expiryDate: expiryDate,
          customerName: 'Test Customer',
          customerAddress: 'Test Address',
          customerEmail: 'test@example.com',
          totalAmount: totalAmount,
          currency: 'AED',
          terms: 'Net 30',
          notes: 'Test data for material forecast analysis',
          lineItems: [
            LineItem(
              itemName: name,
              itemCode: code,
              description: 'Test material: $name',
              quantity: quantity,
              unit: unit,
              unitPrice: unitPrice,
              total: totalAmount,
            ),
          ],
          createdAt: purchaseDate,
          status: 'active',
        );

        generatedPOs.add(po);
        poCounter++;

        // Move to next purchase date
        purchaseDate = purchaseDate.add(Duration(days: intervalDays));
      }

      debugPrint('  ✅ Generated ${numberOfPurchases} POs for $name');
    }

    // Insert all generated POs
    debugPrint('💾 Inserting ${generatedPOs.length} test purchase orders...');
    int successCount = 0;
    int errorCount = 0;

    for (final po in generatedPOs) {
      try {
        await _databaseService.insertPurchaseOrder(po);
        successCount++;
      } catch (e) {
        debugPrint('❌ Error inserting PO ${po.poNumber}: $e');
        errorCount++;
      }
    }

    debugPrint('✅ [Test Data Generator] Completed!');
    debugPrint('  - Successfully inserted: $successCount POs');
    debugPrint('  - Errors: $errorCount');
    debugPrint('  - Total materials: ${testMaterials.length}');
  }

  /// Clears all test purchase orders (POs starting with 'TEST-PO-')
  Future<void> clearTestPurchaseOrders() async {
    debugPrint('🧹 [Test Data Generator] Clearing test purchase orders...');

    try {
      final allPOs = await _databaseService.getAllPurchaseOrders();
      final testPOs = allPOs
          .where((po) => po.poNumber.startsWith('TEST-PO-'))
          .toList();

      debugPrint('  Found ${testPOs.length} test POs to delete');

      for (final po in testPOs) {
        if (po.id != null) {
          await _databaseService.deletePurchaseOrder(po.id!);
        }
      }

      debugPrint(
        '✅ [Test Data Generator] Cleared ${testPOs.length} test purchase orders',
      );
    } catch (e) {
      debugPrint('❌ [Test Data Generator] Error clearing test POs: $e');
      rethrow;
    }
  }
}
