import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/extensions/theme_ext.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../inventory/domain/entities/product.dart';
import '../../../inventory/presentation/controllers/inventory_controller.dart';
import '../../../scanner/presentation/controllers/scanner_controller.dart';

class SaleScreen extends ConsumerStatefulWidget {
  const SaleScreen({super.key});

  @override
  ConsumerState<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends ConsumerState<SaleScreen> {
  final _searchController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  Product? _selectedProduct;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  int get _quantity {
    return int.tryParse(_quantityController.text.trim()) ?? 0;
  }

  bool get _canSell {
    if (_selectedProduct == null) return false;
    final qty = _quantity;
    return qty > 0 && qty <= _selectedProduct!.quantity;
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProduct = product;
      _quantityController.text = '1';
    });
    FocusScope.of(context).unfocus();
  }

  void _clearSelectedProduct() {
    setState(() {
      _selectedProduct = null;
      _quantityController.text = '1';
    });
  }

  void _incrementQty() {
    if (_selectedProduct == null) return;
    final currentVal = _quantity;
    if (currentVal < _selectedProduct!.quantity) {
      setState(() {
        _quantityController.text = '${currentVal + 1}';
      });
    }
  }

  void _decrementQty() {
    final currentVal = _quantity;
    if (currentVal > 1) {
      setState(() {
        _quantityController.text = '${currentVal - 1}';
      });
    }
  }

  Future<void> _executeSale() async {
    if (!_canSell || _selectedProduct == null) return;

    final qty = _quantity;
    final product = _selectedProduct!;

    // Perform sale using the scanner controller (fully synced with barcode scanner logic)
    final success = await ref.read(scannerControllerProvider.notifier).sellProduct(
          productId: product.id,
          productName: product.name,
          productSku: product.sku,
          unitPrice: product.sellingPrice,
          quantity: qty,
        );

    if (!mounted) return;

    if (success) {
      final total = product.sellingPrice * qty;
      // Show gorgeous receipt dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
              const SizedBox(width: 8),
              Text('Sale Complete!', style: AppTypography.h4),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Receipt Details',
                style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.bold, color: ctx.appTextSecondary),
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      style: AppTypography.labelLarge.copyWith(color: ctx.appTextPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    'x$qty',
                    style: AppTypography.bodyMedium.copyWith(color: ctx.appTextSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Unit Price', style: AppTypography.bodySmall.copyWith(color: ctx.appTextSecondary)),
                  Text(Formatters.currency(product.sellingPrice), style: AppTypography.bodyMedium.copyWith(color: ctx.appTextPrimary)),
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Amount', style: AppTypography.labelLarge.copyWith(color: ctx.appTextPrimary)),
                  Text(
                    Formatters.currency(total),
                    style: AppTypography.h4.copyWith(color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Date: ${Formatters.date(DateTime.now())}',
                style: AppTypography.bodySmall.copyWith(color: ctx.appTextTertiary),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(ctx); // Close Dialog
                ref.read(scannerControllerProvider.notifier).reset();
                context.go('/dashboard'); // Go back to dashboard
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } else {
      final state = ref.read(scannerControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.message ?? 'Sale failed. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final scannerState = ref.watch(scannerControllerProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text('New Manual Sale'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSizes.screenPaddingH),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selectedProduct == null) ...[
                // Search field for products
                Text('Search Product', style: AppTypography.h4.copyWith(color: context.appTextPrimary)),
                const SizedBox(height: AppSizes.md),
                TextField(
                  controller: _searchController,
                  style: TextStyle(color: context.appTextPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Enter product name, SKU, or barcode...',
                    hintStyle: TextStyle(color: context.appTextTertiary, fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    filled: true,
                    fillColor: context.appInputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.appCardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.appCardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.lg),

                // Search Results
                productsAsync.when(
                  data: (products) {
                    final filtered = products.where((p) {
                      if (!p.isActive) return false;
                      final nameMatch = p.name.toLowerCase().contains(_searchQuery);
                      final skuMatch = p.sku.toLowerCase().contains(_searchQuery);
                      final barcodeMatch = p.barcode?.toLowerCase().contains(_searchQuery) ?? false;
                      return nameMatch || skuMatch || barcodeMatch;
                    }).toList();

                    if (filtered.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.search_off_rounded, size: 48, color: context.appTextTertiary),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isEmpty ? 'Start typing to find products' : 'No products found',
                                style: AppTypography.bodyMedium.copyWith(color: context.appTextSecondary),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSizes.sm),
                      itemBuilder: (ctx, index) {
                        final product = filtered[index];
                        final isOutOfStock = product.quantity <= 0;

                        return AppCard(
                          onTap: isOutOfStock ? null : () => _selectProduct(product),
                          padding: const EdgeInsets.all(12),
                          child: Opacity(
                            opacity: isOutOfStock ? 0.5 : 1.0,
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: context.appInputFill,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.name,
                                        style: AppTypography.labelLarge.copyWith(color: context.appTextPrimary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'SKU: ${product.sku}',
                                        style: AppTypography.bodySmall.copyWith(color: context.appTextSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      Formatters.currency(product.sellingPrice),
                                      style: AppTypography.labelLarge.copyWith(color: context.appTextPrimary),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isOutOfStock ? 'Out of stock' : '${product.quantity} ${product.unit} left',
                                      style: AppTypography.bodySmall.copyWith(
                                        color: isOutOfStock
                                            ? AppColors.error
                                            : product.isLowStock
                                                ? AppColors.warning
                                                : AppColors.success,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  ),
                  error: (err, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Text('Error loading products: $err', style: TextStyle(color: AppColors.error)),
                    ),
                  ),
                ),
              ] else ...[
                // Selected Product Details Card
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Selected Product', style: AppTypography.h4.copyWith(color: context.appTextPrimary)),
                    TextButton.icon(
                      onPressed: _clearSelectedProduct,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                      label: const Text('Change'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.md),

                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.inventory_2_rounded, color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedProduct!.name,
                              style: AppTypography.labelLarge.copyWith(color: context.appTextPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'SKU: ${_selectedProduct!.sku}',
                              style: AppTypography.bodySmall.copyWith(color: context.appTextSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Stock: ${_selectedProduct!.quantity} ${_selectedProduct!.unit} available',
                              style: AppTypography.bodySmall.copyWith(
                                color: _selectedProduct!.isLowStock ? AppColors.warning : AppColors.success,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.xl),

                // Editable Quantity input with flanking buttons
                Text('Quantity to Sell', style: AppTypography.labelLarge.copyWith(color: context.appTextPrimary)),
                const SizedBox(height: AppSizes.md),
                AppCard(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: _decrementQty,
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        color: AppColors.primary,
                        iconSize: 28,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _quantityController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: AppTypography.h3.copyWith(color: context.appTextPrimary),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                          onChanged: (val) {
                            setState(() {}); // trigger rebuild to update prices
                          },
                          onTap: () => _quantityController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _quantityController.text.length,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _incrementQty,
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        color: AppColors.primary,
                        iconSize: 28,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Validation Messages
                if (_quantity <= 0 && _quantityController.text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'Enter a valid quantity',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                    ),
                  )
                else if (_selectedProduct != null && _quantity > _selectedProduct!.quantity)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'Exceeds available stock (${_selectedProduct!.quantity} left)',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                    ),
                  ),

                const SizedBox(height: AppSizes.xl),

                // Pricing Summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.isDark ? AppColors.primary.withValues(alpha: 0.15) : AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Unit Price', style: AppTypography.bodyMedium.copyWith(color: context.appTextPrimary)),
                          Text(Formatters.currency(_selectedProduct!.sellingPrice),
                              style: AppTypography.labelMedium.copyWith(color: context.appTextPrimary)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Quantity', style: AppTypography.bodyMedium.copyWith(color: context.appTextPrimary)),
                          Text('×$_quantity',
                              style: AppTypography.labelMedium.copyWith(color: context.appTextPrimary)),
                        ],
                      ),
                      Divider(height: 20, color: context.appDivider),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total',
                            style: AppTypography.h4.copyWith(
                              color: context.isDark ? AppColors.primaryLight : AppColors.primaryDark,
                            ),
                          ),
                          Text(
                            Formatters.currency(_selectedProduct!.sellingPrice * _quantity),
                            style: AppTypography.h3.copyWith(
                              color: context.isDark ? AppColors.primaryLight : AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.xxl),

                // Action Button
                AppButton(
                  label: scannerState.isLoading
                      ? 'Processing Sale...'
                      : 'Confirm Sale — ${Formatters.currency(_selectedProduct!.sellingPrice * _quantity)}',
                  isLoading: scannerState.isLoading,
                  onPressed: _canSell && !scannerState.isLoading ? _executeSale : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
