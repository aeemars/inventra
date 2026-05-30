import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../inventory/presentation/controllers/inventory_controller.dart';
import '../../../transactions/presentation/controllers/transaction_logs_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Widget _buildAvatar(String? photoUrl, String? displayName) {
    final initials =
        (displayName?.isNotEmpty == true ? displayName! : 'U')[0].toUpperCase();

    if (photoUrl != null && photoUrl.isNotEmpty) {
      ImageProvider imageProvider;
      if (photoUrl.startsWith('data:')) {
        final base64Str = photoUrl.split(',').last;
        imageProvider = MemoryImage(base64Decode(base64Str));
      } else {
        imageProvider = NetworkImage(photoUrl);
      }
      return CircleAvatar(
        radius: 22,
        backgroundImage: imageProvider,
      );
    }

    return CircleAvatar(
      radius: 22,
      backgroundColor: AppColors.primarySurface,
      child: Text(
        initials,
        style: AppTypography.labelLarge.copyWith(color: AppColors.primary),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final totalProducts = ref.watch(totalProductsProvider);
    final lowStockCount = ref.watch(lowStockCountProvider);
    final inventoryValue = ref.watch(inventoryValueProvider);
    final intakeToday = ref.watch(todayIntakeCountProvider);
    final salesToday = ref.watch(todaySalesCountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSizes.screenPaddingH),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSizes.sm),

              // ── Header ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          user?.shopName?.isNotEmpty == true
                              ? user!.shopName!
                              : 'My Shop',
                          style: AppTypography.h2),
                      const SizedBox(height: 2),
                      Text(
                        'Welcome back, ${user?.displayName.isNotEmpty == true ? user!.displayName : 'User'}',
                        style: AppTypography.bodyMedium
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  // Profile avatar
                  GestureDetector(
                    onTap: () => context.push('/profile'),
                    child: _buildAvatar(user?.photoUrl, user?.displayName),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.xxl),

              // ── Intake & Sales Row ──
              Row(
                children: [
                  Expanded(
                    child: _DashboardSummaryCard(
                      label: 'INTAKE',
                      value: intakeToday,
                      subtitle: 'Items added today',
                      color: const Color(0xFF2E7D32),
                      bgColor: const Color(0xFFE8F5E9),
                      icon: Icons.arrow_downward_rounded,
                      onTap: () => context.push('/transaction-logs'),
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: _DashboardSummaryCard(
                      label: 'SALES',
                      value: salesToday,
                      subtitle: 'Items sold today',
                      color: const Color(0xFFE85D3A),
                      bgColor: const Color(0xFFFFF3E0),
                      icon: Icons.arrow_upward_rounded,
                      onTap: () => context.push('/transaction-logs'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.lg),

              // ── Stat Cards Row ──
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      value: Formatters.number(totalProducts),
                      label: 'Total Products',
                      icon: Icons.inventory_2_outlined,
                      color: AppColors.primary,
                      onTap: () => context.go('/inventory'),
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: _StatCard(
                      value: Formatters.number(lowStockCount),
                      label: 'Low Stock',
                      icon: Icons.warning_amber_rounded,
                      color: AppColors.warning,
                      onTap: () => context.push('/low-stock'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.lg),

              // ── Inventory Value Card ──
              AppCard(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppSizes.lg),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Inventory Value',
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textSecondary)),
                        const SizedBox(height: 2),
                        Text(
                          Formatters.currency(inventoryValue),
                          style: AppTypography.h3,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.xxl),

              // ── Quick Actions ──
              Text('Quick Actions', style: AppTypography.h4),
              const SizedBox(height: AppSizes.md),
              Row(
                children: [
                  _QuickAction(
                    icon: Icons.inventory_2_outlined,
                    label: 'Products',
                    color: AppColors.primary,
                    onTap: () => context.go('/inventory'),
                  ),
                  _QuickAction(
                    icon: Icons.trending_up_rounded,
                    label: 'In-Demand',
                    color: AppColors.coral,
                    onTap: () => context.push('/in-demand'),
                  ),
                  _QuickAction(
                    icon: Icons.receipt_long_rounded,
                    label: 'Logs',
                    color: AppColors.coral,
                    onTap: () => context.push('/transaction-logs'),
                  ),
                  _QuickAction(
                    icon: Icons.bar_chart_rounded,
                    label: 'Reports',
                    color: AppColors.info,
                    onTap: () => context.go('/reporting'),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardSummaryCard extends StatelessWidget {
  final String label;
  final int value;
  final String subtitle;
  final Color color;
  final Color bgColor;
  final IconData icon;
  final VoidCallback onTap;

  const _DashboardSummaryCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.bgColor,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              value,
              style: AppTypography.statMedium,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
