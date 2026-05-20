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
    final productsAsync = ref.watch(productsProvider);

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

              // ── Current Stock Levels Card ──
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Current Stock Levels',
                            style: AppTypography.labelLarge),
                        // Green "All Synced" badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            borderRadius:
                                BorderRadius.circular(AppSizes.radiusFull),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppColors.success,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'All Synced',
                                style: AppTypography.labelSmall
                                    .copyWith(color: AppColors.success),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.xl),

                    // ── Bar Chart (simplified) ──
                    productsAsync.when(
                      data: (products) {
                        // Group by category and show stock bars
                        final categoryStocks = <String, int>{};
                        for (final p in products) {
                          final cat = p.categoryName ?? 'Uncategorized';
                          categoryStocks[cat] =
                              (categoryStocks[cat] ?? 0) + p.quantity;
                        }

                        if (categoryStocks.isEmpty) {
                          return const SizedBox(
                            height: 100,
                            child: Center(
                              child: Text('No products yet',
                                  style:
                                      TextStyle(color: AppColors.textTertiary)),
                            ),
                          );
                        }

                        final maxVal = categoryStocks.values
                            .reduce((a, b) => a > b ? a : b);

                        return Column(
                          children: categoryStocks.entries
                              .take(5)
                              .map((entry) => _StockBar(
                                    label: entry.key,
                                    value: entry.value,
                                    maxValue: maxVal,
                                  ))
                              .toList(),
                        );
                      },
                      loading: () => const SizedBox(
                        height: 100,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (_, __) => const SizedBox(
                        height: 100,
                        child: Center(child: Text('Error loading data')),
                      ),
                    ),
                  ],
                ),
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
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: _StatCard(
                      value: Formatters.number(lowStockCount),
                      label: 'Low Stock',
                      icon: Icons.warning_amber_rounded,
                      color: AppColors.warning,
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

class _StockBar extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;

  const _StockBar({
    required this.label,
    required this.value,
    required this.maxValue,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue > 0 ? value / maxValue : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.inputFill,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: Container(
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              style: AppTypography.labelMedium,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
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
