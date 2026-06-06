import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
                            _showProductDetailSheet(context, product),
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

void _showProductDetailSheet(BuildContext context, dynamic product) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppSizes.screenPaddingH, AppSizes.lg,
            AppSizes.screenPaddingH, AppSizes.xxl,
          ),
          children: [
            // drag handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: AppSizes.lg),
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Status badge
            Row(
              children: [
                Expanded(
                  child: Text(product.name, style: AppTypography.h3),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: product.isOutOfStock
                        ? AppColors.error
                        : product.isLowStock
                            ? AppColors.warning
                            : AppColors.success,
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                  ),
                  child: Text(
                    product.isOutOfStock
                        ? 'Out of Stock'
                        : product.isLowStock ? 'Low Stock' : 'In Stock',
                    style: AppTypography.labelSmall.copyWith(color: AppColors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            _DetailRow(label: 'SKU', value: product.sku),
            if (product.barcode != null)
              _DetailRow(label: 'Barcode', value: product.barcode!),
            _DetailRow(
              label: 'Category',
              value: product.categoryName ?? 'Uncategorized',
            ),
            _DetailRow(
              label: 'Selling Price',
              value: Formatters.currency(product.sellingPrice),
            ),
            _DetailRow(
              label: 'Cost Price',
              value: Formatters.currency(product.costPrice),
            ),
            _DetailRow(
              label: 'Stock',
              value: '${product.quantity} ${product.unit}',
            ),
            _DetailRow(
              label: 'Reorder Level',
              value: '${product.reorderLevel} ${product.unit}',
            ),
            if (product.supplier != null)
              _DetailRow(label: 'Supplier', value: product.supplier!),
            if (product.expiryDate != null)
              _DetailRow(
                label: 'Expiry',
                value: Formatters.date(product.expiryDate!),
              ),
            if (product.description != null)
              _DetailRow(label: 'Description', value: product.description!),
          ],
        ),
      ),
    ),
  );
}

// reusable row for the detail sheet
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: AppTypography.bodyMedium),
          ),
        ],
      ),
    );
  }
}
