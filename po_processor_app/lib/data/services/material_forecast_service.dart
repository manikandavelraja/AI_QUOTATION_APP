import 'package:flutter/foundation.dart' show debugPrint;
import '../../domain/entities/material_forecast.dart';
import 'database_service.dart';
import 'dart:math' as math;

class MaterialForecastService {
  final DatabaseService _databaseService = DatabaseService.instance;

  /// Analyzes material procurement data for a specific material code
  Future<MaterialForecast?> analyzeMaterial(String materialCode) async {
    try {
      debugPrint(
        '🔍 [Material Forecast Service] Starting analysis for material code: "$materialCode"',
      );

      // Get all purchase orders
      debugPrint(
        '🔍 [Material Forecast Service] Fetching all purchase orders...',
      );
      final allPOs = await _databaseService.getAllPurchaseOrders();
      debugPrint(
        '✅ [Material Forecast Service] Found ${allPOs.length} purchase orders',
      );

      // Filter line items by material code (case-insensitive)
      final materialPurchases = <PurchaseEvent>[];
      String? materialName;

      final now = DateTime.now();
      // Calculate 12 months ago properly
      final twelveMonthsAgo = DateTime(now.year - 1, now.month, now.day);
      debugPrint(
        '📅 [Material Forecast Service] Filtering purchases from: ${twelveMonthsAgo.toString()} to ${now.toString()}',
      );

      final searchCode = materialCode.toLowerCase().trim();
      debugPrint(
        '🔍 [Material Forecast Service] Searching for material code (normalized): "$searchCode"',
      );

      int totalLineItems = 0;
      int itemsWithCode = 0;
      int matchingItems = 0;

      for (final po in allPOs) {
        debugPrint(
          '📋 [Material Forecast Service] Processing PO: ${po.poNumber} (${po.lineItems.length} line items)',
        );
        for (final item in po.lineItems) {
          totalLineItems++;
          final itemCode = item.itemCode?.trim() ?? '';

          if (itemCode.isNotEmpty) {
            itemsWithCode++;
            final normalizedItemCode = itemCode.toLowerCase();
            debugPrint(
              '  📦 Item: "${item.itemName}" | Code: "$itemCode" | Normalized: "$normalizedItemCode"',
            );

            // More flexible matching - check if codes match (exact match first, then partial)
            bool codesMatch = false;
            if (normalizedItemCode == searchCode) {
              codesMatch = true;
              debugPrint('  ✅ Exact match found!');
            } else if (normalizedItemCode.contains(searchCode) ||
                searchCode.contains(normalizedItemCode)) {
              codesMatch = true;
              debugPrint('  ✅ Partial match found!');
            }

            if (codesMatch) {
              matchingItems++;
              debugPrint(
                '  ✅ MATCH FOUND! Item code: "$itemCode" matches search: "$materialCode"',
              );
              materialName ??= item.itemName;

              // Check date filter - be more lenient (allow 1 day buffer)
              final isWithin12Months =
                  po.poDate.isAfter(
                    twelveMonthsAgo.subtract(const Duration(days: 1)),
                  ) ||
                  po.poDate.isAtSameMomentAs(twelveMonthsAgo);
              debugPrint(
                '  📅 PO Date: ${po.poDate.toString()} | Cutoff: ${twelveMonthsAgo.toString()} | Within 12 months: $isWithin12Months',
              );

              // Include purchase if within date range, or if we have very few purchases, include all
              if (isWithin12Months || materialPurchases.length < 2) {
                // Calculate lead time: difference between PO date and expiry date
                // This represents the time from order to expected delivery/expiry
                final leadTimeDays = po.expiryDate.difference(po.poDate).inDays;

                materialPurchases.add(
                  PurchaseEvent(
                    purchaseDate: po.poDate,
                    quantity: item.quantity,
                    unit: item.unit,
                    poNumber: po.poNumber,
                    leadTimeDays: leadTimeDays.toString(),
                  ),
                );
                debugPrint(
                  '  ✅ Added purchase: ${item.quantity} ${item.unit} on ${po.poDate.toString()} (Lead time: $leadTimeDays days)',
                );
              } else {
                debugPrint(
                  '  ⏭️ Skipped (outside 12 month window, but we already have ${materialPurchases.length} purchases)',
                );
              }
            }
          } else {
            debugPrint('  ⚠️ Item "${item.itemName}" has no item code');
          }
        }
      }

      debugPrint('📊 [Material Forecast Service] Summary:');
      debugPrint('  - Total line items: $totalLineItems');
      debugPrint('  - Items with code: $itemsWithCode');
      debugPrint('  - Matching items: $matchingItems');
      debugPrint('  - Purchases added: ${materialPurchases.length}');

      if (materialPurchases.isEmpty) {
        debugPrint(
          '❌ [Material Forecast Service] No purchases found for material code: "$materialCode"',
        );
        debugPrint(
          '💡 [Material Forecast Service] Tip: Check if the material code in POs matches exactly (case-insensitive)',
        );
        return null; // No data found for this material code
      }

      debugPrint(
        '✅ [Material Forecast Service] Found ${materialPurchases.length} purchases for analysis',
      );

      // Sort by purchase date
      materialPurchases.sort(
        (a, b) => a.purchaseDate.compareTo(b.purchaseDate),
      );

      // Calculate statistics
      final totalQuantity = materialPurchases.fold<double>(
        0.0,
        (sum, purchase) => sum + purchase.quantity,
      );

      final purchaseCount = materialPurchases.length;

      // Calculate average lead time
      final leadTimes = materialPurchases
          .where((p) => p.leadTimeDays != null)
          .map((p) => double.tryParse(p.leadTimeDays!) ?? 0.0)
          .where((lt) => lt > 0)
          .toList();

      final averageLeadTimeDays = leadTimes.isNotEmpty
          ? leadTimes.reduce((a, b) => a + b) / leadTimes.length
          : 30.0; // Default to 30 days if no lead time data

      // Calculate purchase intervals
      final intervals = <int>[];
      for (int i = 1; i < materialPurchases.length; i++) {
        final daysBetween = materialPurchases[i].purchaseDate
            .difference(materialPurchases[i - 1].purchaseDate)
            .inDays;
        if (daysBetween > 0) {
          intervals.add(daysBetween);
        }
      }

      final averageDaysBetweenPurchases = intervals.isNotEmpty
          ? intervals.reduce((a, b) => a + b) / intervals.length
          : 0.0;

      // Calculate consumption rate (total quantity / 12 months)
      final monthsOfData = _calculateMonthsBetween(
        materialPurchases.first.purchaseDate,
        materialPurchases.last.purchaseDate,
      );
      final consumptionRatePerMonth = monthsOfData > 0
          ? totalQuantity / monthsOfData
          : totalQuantity / 12.0; // Default to 12 months if calculation fails

      // Calculate purchase frequency consistency (coefficient of variation)
      // Lower variation = more consistent = better for stocking
      double purchaseFrequencyConsistency = 1.0;
      if (intervals.isNotEmpty && averageDaysBetweenPurchases > 0) {
        final variance =
            intervals
                .map((i) => math.pow(i - averageDaysBetweenPurchases, 2))
                .reduce((a, b) => a + b) /
            intervals.length;
        final standardDeviation = math.sqrt(variance);
        final coefficientOfVariation =
            standardDeviation / averageDaysBetweenPurchases;
        // Convert to consistency score (0-1), where 1 is most consistent
        purchaseFrequencyConsistency = math.max(
          0.0,
          1.0 - (coefficientOfVariation / 2.0),
        );
      }

      // Predict next order date
      DateTime? predictedNextOrderDate;
      if (materialPurchases.isNotEmpty && averageDaysBetweenPurchases > 0) {
        final lastPurchaseDate = materialPurchases.last.purchaseDate;
        predictedNextOrderDate = lastPurchaseDate.add(
          Duration(days: averageDaysBetweenPurchases.round()),
        );
      }

      // Decision Engine: Stock vs. Do Not Stock
      final recommendation = _determineRecommendation(
        purchaseCount: purchaseCount,
        averageDaysBetweenPurchases: averageDaysBetweenPurchases,
        purchaseFrequencyConsistency: purchaseFrequencyConsistency,
        averageLeadTimeDays: averageLeadTimeDays,
        consumptionRatePerMonth: consumptionRatePerMonth,
      );

      return MaterialForecast(
        materialCode: materialCode,
        materialName: materialName ?? materialCode,
        averageLeadTimeDays: averageLeadTimeDays,
        consumptionRatePerMonth: consumptionRatePerMonth,
        predictedNextOrderDate: predictedNextOrderDate,
        recommendation: recommendation['decision'] as String,
        recommendationReason: recommendation['reason'] as String,
        purchaseHistory: materialPurchases,
        totalQuantityLast12Months: totalQuantity,
        purchaseCountLast12Months: purchaseCount,
        averageDaysBetweenPurchases: averageDaysBetweenPurchases,
        purchaseFrequencyConsistency: purchaseFrequencyConsistency,
      );
    } catch (e) {
      throw Exception('Error analyzing material: $e');
    }
  }

  /// Determines whether to stock or not stock based on analysis
  Map<String, String> _determineRecommendation({
    required int purchaseCount,
    required double averageDaysBetweenPurchases,
    required double purchaseFrequencyConsistency,
    required double averageLeadTimeDays,
    required double consumptionRatePerMonth,
  }) {
    // Decision criteria:
    // 1. Need at least 3 purchases in 12 months to consider stocking
    // 2. Purchase frequency should be relatively consistent (consistency > 0.5)
    // 3. If lead time is long (>30 days), more reason to stock
    // 4. If consumption rate is high, more reason to stock
    // 5. If average days between purchases is short (<60 days), more reason to stock

    if (purchaseCount < 3) {
      return {
        'decision': 'Do Not Stock',
        'reason':
            'Insufficient purchase history (less than 3 purchases in the last 12 months). Order on-demand.',
      };
    }

    final shouldStock =
        purchaseFrequencyConsistency > 0.5 &&
        (averageDaysBetweenPurchases < 60 ||
            averageLeadTimeDays > 30 ||
            consumptionRatePerMonth > 10);

    if (shouldStock) {
      String reason = 'Recommended to stock because:';
      if (purchaseFrequencyConsistency > 0.5) {
        reason += ' Purchase pattern is consistent';
      }
      if (averageDaysBetweenPurchases < 60) {
        reason +=
            ', Frequent purchases (every ${averageDaysBetweenPurchases.toStringAsFixed(0)} days)';
      }
      if (averageLeadTimeDays > 30) {
        reason +=
            ', Long lead time (${averageLeadTimeDays.toStringAsFixed(0)} days)';
      }
      if (consumptionRatePerMonth > 10) {
        reason +=
            ', High consumption rate (${consumptionRatePerMonth.toStringAsFixed(1)} units/month)';
      }
      reason += '.';

      return {'decision': 'Stock', 'reason': reason};
    } else {
      String reason = 'Recommended not to stock because:';
      if (purchaseFrequencyConsistency <= 0.5) {
        reason += ' Purchase pattern is inconsistent';
      }
      if (averageDaysBetweenPurchases >= 60) {
        reason +=
            ', Infrequent purchases (every ${averageDaysBetweenPurchases.toStringAsFixed(0)} days)';
      }
      if (averageLeadTimeDays <= 30) {
        reason +=
            ', Short lead time (${averageLeadTimeDays.toStringAsFixed(0)} days)';
      }
      if (consumptionRatePerMonth <= 10) {
        reason +=
            ', Low consumption rate (${consumptionRatePerMonth.toStringAsFixed(1)} units/month)';
      }
      reason += '. Order on-demand.';

      return {'decision': 'Do Not Stock', 'reason': reason};
    }
  }

  /// Calculate months between two dates
  double _calculateMonthsBetween(DateTime start, DateTime end) {
    final years = end.year - start.year;
    final months = end.month - start.month;
    final days = end.day - start.day;
    return (years * 12) + months + (days / 30.0);
  }

  /// Get all unique material codes from purchase orders
  Future<List<String>> getAllMaterialCodes() async {
    try {
      final allPOs = await _databaseService.getAllPurchaseOrders();
      final materialCodes = <String>{};

      for (final po in allPOs) {
        for (final item in po.lineItems) {
          if (item.itemCode != null && item.itemCode!.trim().isNotEmpty) {
            materialCodes.add(item.itemCode!.trim());
          }
        }
      }

      return materialCodes.toList()..sort();
    } catch (e) {
      throw Exception('Error fetching material codes: $e');
    }
  }
}
