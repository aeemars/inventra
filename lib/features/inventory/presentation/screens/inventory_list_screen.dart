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
                        onTap: () => context.push('/inventory/${product.id}'),
                      );
                    },
                  ),
          ),
        ],
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
              Text('Filter & Sort', style: AppTypography.h4),
              const SizedBox(height: AppSizes.xl),
              // Category filter chips would go here
              Text('Sort By', style: AppTypography.labelLarge),
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
