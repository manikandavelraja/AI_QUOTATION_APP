import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/screens/login_screen.dart';
import '../../presentation/screens/dashboard_screen.dart';
import '../../presentation/screens/upload_po_screen.dart';
import '../../presentation/screens/po_list_screen.dart';
import '../../presentation/screens/po_detail_screen.dart';
import '../../presentation/screens/settings_screen.dart';
import '../../presentation/screens/inquiry_list_screen.dart';
import '../../presentation/screens/inquiry_detail_screen.dart';
import '../../presentation/screens/upload_inquiry_screen.dart';
import '../../presentation/screens/create_quotation_screen.dart';
import '../../presentation/screens/supplier_order_list_screen.dart';
import '../../presentation/screens/supplier_order_detail_screen.dart';
import '../../presentation/screens/supplier_order_create_screen.dart';
import '../../presentation/screens/delivery_document_list_screen.dart';
import '../../presentation/screens/delivery_document_detail_screen.dart';
import '../../presentation/screens/delivery_document_create_screen.dart';
import '../../presentation/screens/quotation_list_screen.dart';
import '../../presentation/screens/quotation_detail_screen.dart';
import '../../presentation/screens/splash_screen.dart';
import '../../presentation/screens/material_forecast_screen.dart';

/// Global navigator key for safe navigation from background tasks (e.g. after
/// inquiry/PO sync completes when the user may be on a different screen).
final GlobalKey<NavigatorState>? rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  static final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Page Not Found (404)',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'The requested page "${state.uri.path}" does not exist.',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    ),
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/upload',
        name: 'upload',
        builder: (context, state) => const UploadPOScreen(),
      ),
      GoRoute(
        path: '/po-list',
        name: 'po-list',
        builder: (context, state) => const POListScreen(),
      ),
      GoRoute(
        path: '/po-detail/:id',
        name: 'po-detail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return PODetailScreen(poId: id);
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      // Inquiry routes
      GoRoute(
        path: '/inquiry-list',
        name: 'inquiry-list',
        builder: (context, state) => const InquiryListScreen(),
      ),
      GoRoute(
        path: '/inquiry-detail/:id',
        name: 'inquiry-detail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return InquiryDetailScreen(inquiryId: id);
        },
      ),
      GoRoute(
        path: '/upload-inquiry',
        name: 'upload-inquiry',
        builder: (context, state) => const UploadInquiryScreen(),
      ),
      GoRoute(
        path: '/create-quotation/:inquiryId',
        name: 'create-quotation',
        builder: (context, state) {
          final inquiryId = state.pathParameters['inquiryId']!;
          return CreateQuotationScreen(inquiryId: inquiryId);
        },
      ),
      GoRoute(
        path: '/quotation-list',
        name: 'quotation-list',
        builder: (context, state) => const QuotationListScreen(),
      ),
      GoRoute(
        path: '/quotation-detail/:id',
        name: 'quotation-detail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return QuotationDetailScreen(quotationId: id);
        },
      ),
      // Supplier Order routes
      GoRoute(
        path: '/supplier-order-list',
        name: 'supplier-order-list',
        builder: (context, state) => const SupplierOrderListScreen(),
      ),
      GoRoute(
        path: '/supplier-order-detail/:id',
        name: 'supplier-order-detail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return SupplierOrderDetailScreen(orderId: id);
        },
      ),
      GoRoute(
        path: '/supplier-order-create',
        name: 'supplier-order-create',
        builder: (context, state) {
          final poId = state.uri.queryParameters['poId'];
          return SupplierOrderCreateScreen(poId: poId);
        },
      ),
      // Delivery Document routes
      GoRoute(
        path: '/delivery-document-list',
        name: 'delivery-document-list',
        builder: (context, state) => const DeliveryDocumentListScreen(),
      ),
      GoRoute(
        path: '/delivery-document-detail/:id',
        name: 'delivery-document-detail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return DeliveryDocumentDetailScreen(documentId: id);
        },
      ),
      GoRoute(
        path: '/delivery-document-create',
        name: 'delivery-document-create',
        builder: (context, state) {
          final supplierOrderId = state.uri.queryParameters['supplierOrderId'];
          final poId = state.uri.queryParameters['poId'];
          return DeliveryDocumentCreateScreen(
            supplierOrderId: supplierOrderId,
            poId: poId,
          );
        },
      ),
      GoRoute(
        path: '/delivery-document-create/:supplierOrderId',
        name: 'delivery-document-create-from-order',
        builder: (context, state) {
          final supplierOrderId = state.pathParameters['supplierOrderId']!;
          return DeliveryDocumentCreateScreen(supplierOrderId: supplierOrderId);
        },
      ),
      // Material Forecast route
      GoRoute(
        path: '/material-forecast',
        name: 'material-forecast',
        builder: (context, state) => const MaterialForecastScreen(),
      ),
    ],
  );
}

