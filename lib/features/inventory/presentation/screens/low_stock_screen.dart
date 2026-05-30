import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/extensions/theme_ext.dart';
import '../controllers/inventory_controller.dart';

class LowStockScreen extends ConsumerWidget {
  const LowStockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(lowStockProductsProvider);
    final sortedProducts = [...products]..sort((a, b) {
        final aGroup = a.isOutOfStock ? 0 : 1;
        final bGroup = b.isOutOfStock ? 0 : 1;
        if (aGroup != bGroup) return aGroup.compareTo(bGroup);
        return a.quantity.compareTo(b.quantity);
      });

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text('Low Stock Items'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPaddingH,
              AppSizes.lg,
              AppSizes.screenPaddingH,
              AppSizes.md,
            ),
            child: AppCard(
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.warning,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppSizes.lg),
                  Expanded(
                    child: Text(
                      '${Formatters.number(sortedProducts.length)} items need attention',
                      style: AppTypography.bodyMedium
                          .copyWith(color: context.appTextPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: sortedProducts.isEmpty
                ? const EmptyState(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'All stocked up',
                    subtitle: 'No products are running low right now.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSizes.screenPaddingH,
                      AppSizes.sm,
                      AppSizes.screenPaddingH,
                      AppSizes.xl,
                    ),
                    itemCount: sortedProducts.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSizes.sm),
                    itemBuilder: (context, index) {
                      final product = sortedProducts[index];
                      final statusColor = product.isOutOfStock
                          ? AppColors.error
                          : AppColors.warning;

                      return AppCard(
                        onTap: () =>
                            context.push('/inventory/${product.id}/edit'),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.inventory_2_outlined,
                                color: AppColors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: AppSizes.lg),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: AppTypography.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: context.appTextPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    product.categoryName ?? 'Uncategorized',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: context.appTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSizes.md,
                                    vertical: AppSizes.xs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    borderRadius: BorderRadius.circular(
                                        AppSizes.radiusFull),
                                  ),
                                  child: Text(
                                    '${Formatters.number(product.quantity)} ${product.unit}',
                                    style: AppTypography.labelMedium
                                        .copyWith(color: AppColors.white),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'min ${product.reorderLevel}',
                                  style: AppTypography.labelSmall
                                      .copyWith(color: context.appTextTertiary),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
