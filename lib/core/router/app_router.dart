import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/profile_screen.dart';
import '../../features/auth/presentation/screens/shop_setup_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';

import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/inventory/presentation/screens/inventory_list_screen.dart';
import '../../features/inventory/presentation/screens/add_edit_product_screen.dart';
import '../../features/edit/presentation/screens/edit_products_screen.dart';
import '../../features/scanner/presentation/screens/scanner_screen.dart';
import '../../features/sales/presentation/screens/sale_screen.dart';
import '../../features/sales/presentation/screens/sales_queue_screen.dart';
import '../../features/scanner/presentation/screens/scan_history_screen.dart';
import '../../features/analytics/presentation/screens/reporting_screen.dart';
import '../../features/transactions/presentation/screens/transaction_logs_screen.dart';
import '../../features/in_demand/presentation/screens/in_demand_screen.dart';
import '../../features/inventory/presentation/screens/low_stock_screen.dart';
import '../constants/app_colors.dart';
import '../extensions/theme_ext.dart';
import 'scanner_route_access.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      // Don't redirect on splash, login, forgot-password, or shop-setup
      const publicRoutes = ['/', '/login', '/forgot-password', '/shop-setup'];
      if (publicRoutes.contains(loc)) return null;

      final user = ref.read(currentUserProvider);
      if (user != null && !user.hasShop) {
        return '/shop-setup';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/forgot-password',
          builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(
          path: '/shop-setup',
          builder: (_, __) => const ShopSetupScreen()),


      // Main app with bottom nav
      ShellRoute(
        builder: (context, state, child) =>
            _MainShell(state: state, child: child),
        routes: [
          GoRoute(
              path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(
              path: '/inventory',
              builder: (_, __) => const InventoryListScreen()),
          GoRoute(
            path: '/scanner',
            builder: (_, state) =>
                ScannerScreen(reason: state.uri.queryParameters['reason']),
          ),
          GoRoute(
              path: '/edit', builder: (_, __) => const EditProductsScreen()),
          GoRoute(
              path: '/reporting', builder: (_, __) => const ReportingScreen()),
        ],
      ),

      // Sub-routes
      GoRoute(
        path: '/inventory/add',
        redirect: (_, __) {
          final allowed = ref
              .read(scannerRouteAccessProvider.notifier)
              .consumeIfValid(ScannerProtectedRoute.addProduct);
          return allowed ? null : '/scanner?reason=restricted';
        },
        builder: (_, state) => AddEditProductScreen(
          initialBarcode: state.uri.queryParameters['barcode'],
          forceNew: state.uri.queryParameters['forceNew'] == 'true',
        ),
      ),
      GoRoute(
        path: '/inventory/auto-generate',
        builder: (_, __) => const AddEditProductScreen(autoGenerate: true),
      ),
      GoRoute(
          path: '/inventory/:id/edit',
          builder: (_, state) =>
              AddEditProductScreen(productId: state.pathParameters['id'])),
      GoRoute(path: '/sales-queue', builder: (_, __) => const SalesQueueScreen()),
      GoRoute(path: '/sale', builder: (_, __) => const SaleScreen()),
      GoRoute(
          path: '/scan-history', builder: (_, __) => const ScanHistoryScreen()),
      GoRoute(
          path: '/transaction-logs',
          builder: (_, __) => const TransactionLogsScreen()),
      GoRoute(path: '/low-stock', builder: (_, __) => const LowStockScreen()),
      GoRoute(path: '/in-demand', builder: (_, __) => const InDemandScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    ],
  );
});

class _MainShell extends StatelessWidget {
  final Widget child;
  final GoRouterState state;

  const _MainShell({required this.child, required this.state});

  int _currentIndex(String location) {
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/inventory')) return 1;
    if (location.startsWith('/scanner')) return 2;
    if (location.startsWith('/edit')) return 3;
    if (location.startsWith('/reporting')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(state.uri.path);
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.appSurface,
          boxShadow: [
            BoxShadow(
                color: context.isDark ? Colors.black.withValues(alpha: 0.2) : AppColors.shadow,
                blurRadius: 8,
                offset: const Offset(0, -2))
          ],
          border: Border(
            top: BorderSide(color: context.appCardBorder, width: 0.5),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                    icon: Icons.dashboard_outlined,
                    activeIcon: Icons.dashboard_rounded,
                    label: 'Dashboard',
                    isActive: idx == 0,
                    onTap: () => context.go('/dashboard')),
                _NavItem(
                    icon: Icons.inventory_2_outlined,
                    activeIcon: Icons.inventory_2_rounded,
                    label: 'Products',
                    isActive: idx == 1,
                    onTap: () => context.go('/inventory')),
                // Center Scanner FAB
                GestureDetector(
                  onTap: () => context.go('/scanner'),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded,
                        color: AppColors.white, size: 26),
                  ),
                ),
                _NavItem(
                    icon: Icons.edit_note_outlined,
                    activeIcon: Icons.edit_note_rounded,
                    label: 'Edit',
                    isActive: idx == 3,
                    onTap: () => context.go('/edit')),
                _NavItem(
                    icon: Icons.bar_chart_outlined,
                    activeIcon: Icons.bar_chart_rounded,
                    label: 'Reports',
                    isActive: idx == 4,
                    onTap: () => context.go('/reporting')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon, activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem(
      {required this.icon,
      required this.activeIcon,
      required this.label,
      required this.isActive,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final activeColor = context.isDark ? AppColors.primaryLight : AppColors.primary;
    final inactiveColor = context.appTextTertiary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isActive ? activeIcon : icon,
                size: 24,
                color: isActive ? activeColor : inactiveColor),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.visible,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color:
                        isActive ? activeColor : inactiveColor)),
          ],
        ),
      ),
    );
  }
}
