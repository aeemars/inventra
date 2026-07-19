import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/extensions/theme_ext.dart';
import '../controllers/inventory_controller.dart';

/// Inventory list screen with search, filter, sort
class InventoryListScreen extends ConsumerWidget {
  const InventoryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(filteredProductsProvider);
    final searchQuery = ref.watch(productSearchQueryProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: () => _showFilterSheet(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search Bar ──
          Padding(
            padding: const EdgeInsets.all(AppSizes.screenPaddingH),
            child: AppTextField(
              hint: 'Search products...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              onChanged: (value) {
                ref.read(productSearchQueryProvider.notifier).state = value;
              },
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        ref.read(productSearchQueryProvider.notifier).state =
                            '';
                      },
                    )
                  : null,
            ),
          ),

          // ── Count Badge ──
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSizes.screenPaddingH),
            child: Row(
              children: [
                Text(
                  '${products.length} product${products.length != 1 ? 's' : ''}',
                  style: AppTypography.bodySmall
                      .copyWith(color: context.appTextSecondary),
                ),
                const Spacer(),
                _SortDropdown(),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.sm),

          // ── Product List ──
          Expanded(
            child: products.isEmpty
                ? EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: searchQuery.isNotEmpty
                        ? 'No results found'
                        : 'No products yet',
                    subtitle: searchQuery.isNotEmpty
                        ? 'Try a different search term'
                        : 'Use Scanner to add your first product',
                    actionLabel: null,
                    onAction: null,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.screenPaddingH),
                    itemCount: products.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSizes.sm),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return _ProductListTile(
                        product: product,
                        onTap: () => _showProductDetailSheet(context, product),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddProductOptions(context, ref),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Product',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _showAddProductOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ctx.appSurfaceRaised,
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ctx.appTextTertiary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text('Add Product',
                  style: AppTypography.h3.copyWith(color: ctx.appTextPrimary)),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded,
                      color: AppColors.primary),
                ),
                title: const Text('Scan Barcode'),
                subtitle: Text('Scan physical barcode using camera',
                    style: TextStyle(color: ctx.appTextTertiary, fontSize: 13)),
                onTap: () {
                  Navigator.pop(ctx);
                  context.go('/scanner');
                },
              ),
              Divider(height: 1, indent: 70, color: ctx.appTextTertiary.withValues(alpha: 0.15)),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: AppColors.primary),
                ),
                title: const Text('Auto-Generate Barcode'),
                subtitle: Text('Create product with a unique generated code',
                    style: TextStyle(color: ctx.appTextTertiary, fontSize: 13)),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/inventory/auto-generate');
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(AppSizes.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter & Sort',
                style: AppTypography.h4.copyWith(color: context.appTextPrimary),
              ),
              const SizedBox(height: AppSizes.xl),
              // Category filter chips would go here
              Text(
                'Sort By',
                style: AppTypography.labelLarge.copyWith(color: context.appTextPrimary),
              ),
              const SizedBox(height: AppSizes.md),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ProductSort.values.map((sort) {
                  final isSelected = ref.read(productSortProvider) == sort;
                  return ChoiceChip(
                    label: Text(_sortLabel(sort)),
                    selected: isSelected,
                    onSelected: (_) {
                      ref.read(productSortProvider.notifier).state = sort;
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSizes.xxl),
            ],
          ),
        );
      },
    );
  }

  String _sortLabel(ProductSort sort) {
    switch (sort) {
      case ProductSort.newest:
        return 'Newest';
      case ProductSort.oldest:
        return 'Oldest';
      case ProductSort.nameAZ:
        return 'Name A-Z';
      case ProductSort.nameZA:
        return 'Name Z-A';
      case ProductSort.priceLowHigh:
        return 'Price ↑';
      case ProductSort.priceHighLow:
        return 'Price ↓';
      case ProductSort.stockLowHigh:
        return 'Stock ↑';
    }
  }
}

class _SortDropdown extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SizedBox.shrink();
  }
}

class _ProductListTile extends StatelessWidget {
  final dynamic product;
  final VoidCallback onTap;

  const _ProductListTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // ── Product Image ──
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: context.appInputFill,
              borderRadius: BorderRadius.circular(10),
              image: product.imageUrl != null
                  ? DecorationImage(
                      image: NetworkImage(product.imageUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: product.imageUrl == null
                ? Icon(Icons.inventory_2_outlined,
                    color: context.appTextTertiary, size: 24)
                : null,
          ),
          const SizedBox(width: 12),

          // ── Product Info ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: AppTypography.labelLarge
                      .copyWith(color: context.appTextPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'SKU: ${product.sku}',
                  style: AppTypography.bodySmall
                      .copyWith(color: context.appTextTertiary),
                ),
              ],
            ),
          ),

          // ── Price & Stock ──
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Formatters.currency(product.sellingPrice),
                style: AppTypography.labelLarge,
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _stockColor(product).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                ),
                child: Text(
                  '${product.quantity} ${product.unit}',
                  style: AppTypography.labelSmall
                      .copyWith(color: _stockColor(product)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _stockColor(dynamic product) {
    if (product.isOutOfStock) return AppColors.error;
    if (product.isLowStock) return AppColors.warning;
    return AppColors.success;
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
                  color: context.appDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Status badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: AppTypography.h3.copyWith(color: context.appTextPrimary),
                  ),
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
            const SizedBox(height: AppSizes.lg),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                context.push(
                    '/inventory/print-labels?productId=${product.id}');
              },
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Print Barcode Label'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
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
                color: context.appTextSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodyMedium.copyWith(
                color: context.appTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
