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
import '../../../scanner/presentation/controllers/scanner_controller.dart';
import '../controllers/sales_queue_provider.dart';

class SalesQueueScreen extends ConsumerStatefulWidget {
  const SalesQueueScreen({super.key});

  @override
  ConsumerState<SalesQueueScreen> createState() => _SalesQueueScreenState();
}

class _SalesQueueScreenState extends ConsumerState<SalesQueueScreen> {
  final Map<String, TextEditingController> _qtyControllers = {};

  TextEditingController _controllerFor(String productId, int currentQty) {
    final controller = _qtyControllers.putIfAbsent(
      productId,
      () => TextEditingController(text: '$currentQty'),
    );
    // Sync if provider quantity changed externally (e.g. +/- buttons)
    if (controller.text != '$currentQty') {
      controller.text = '$currentQty';
    }
    return controller;
  }

  void _onQtySubmitted(String productId, String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null && parsed > 0) {
      ref.read(salesQueueProvider.notifier).updateQuantity(productId, parsed);
    } else {
      // Reset to current quantity if invalid
      final queue = ref.read(salesQueueProvider);
      final item = queue.firstWhere((i) => i.product.id == productId);
      _qtyControllers[productId]?.text = '${item.quantity}';
    }
  }

  @override
  void dispose() {
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(salesQueueProvider);
    final subtotal = ref.watch(salesQueueSubtotalProvider);

    // Clean up controllers for removed items
    _qtyControllers.removeWhere((id, c) {
      final exists = queue.any((item) => item.product.id == id);
      if (!exists) c.dispose();
      return !exists;
    });

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: Text('Review Sale', style: TextStyle(color: context.appTextPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: context.appTextPrimary),
      ),
      body: queue.isEmpty
          ? Center(
              child: Text(
                'No items in this sale',
                style: AppTypography.bodyMedium.copyWith(color: context.appTextSecondary),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSizes.screenPaddingH),
              itemCount: queue.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSizes.sm),
              itemBuilder: (context, index) {
                final item = queue[index];
                final qtyController = _controllerFor(item.product.id, item.quantity);
                return AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.product.name,
                              style: AppTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: context.appTextPrimary,
                              ),
                            ),
                            Text(
                              Formatters.currency(item.product.sellingPrice),
                              style: AppTypography.bodySmall.copyWith(color: context.appTextSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => ref
                            .read(salesQueueProvider.notifier)
                            .updateQuantity(item.product.id, item.quantity - 1),
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        color: AppColors.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                      SizedBox(
                        width: 44,
                        child: TextField(
                          controller: qtyController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: context.appTextPrimary,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            filled: true,
                            fillColor: context.appInputFill,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: context.appCardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: context.appCardBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                          ),
                          onSubmitted: (val) => _onQtySubmitted(item.product.id, val),
                          onTapOutside: (_) {
                            _onQtySubmitted(item.product.id, qtyController.text);
                            FocusScope.of(context).unfocus();
                          },
                        ),
                      ),
                      IconButton(
                        onPressed: () => ref
                            .read(salesQueueProvider.notifier)
                            .updateQuantity(item.product.id, item.quantity + 1),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        color: AppColors.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: AppSizes.sm),
                      SizedBox(
                        width: 80,
                        child: Text(
                          Formatters.currency(item.lineTotal),
                          textAlign: TextAlign.right,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: context.appTextPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => ref
                            .read(salesQueueProvider.notifier)
                            .removeItem(item.product.id),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: AppColors.error,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: queue.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.screenPaddingH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: AppTypography.h4.copyWith(color: context.appTextPrimary)),
                        Text(
                          Formatters.currency(subtotal),
                          style: AppTypography.h4.copyWith(color: AppColors.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.md),
                    AppButton(
                      label: 'Proceed — ${Formatters.currency(subtotal)}',
                      onPressed: () => _showConfirmSheet(context, queue, subtotal),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  void _showConfirmSheet(
    BuildContext context,
    List queue,
    double subtotal,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SaleConfirmSheet(
        queue: queue,
        subtotal: subtotal,
      ),
    );
  }
}

class _SaleConfirmSheet extends ConsumerStatefulWidget {
  final List queue;
  final double subtotal;

  const _SaleConfirmSheet({required this.queue, required this.subtotal});

  @override
  ConsumerState<_SaleConfirmSheet> createState() => _SaleConfirmSheetState();
}

class _SaleConfirmSheetState extends ConsumerState<_SaleConfirmSheet> {
  bool _isProcessing = false;

  Future<void> _completeSale() async {
    setState(() => _isProcessing = true);

    final queue = ref.read(salesQueueProvider);
    final success = await ref
        .read(scannerControllerProvider.notifier)
        .completeMultiItemSale(queue);

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      ref.read(salesQueueProvider.notifier).clear();
      Navigator.pop(context); // close the sheet
      if (context.mounted) {
        context.showAppSnackBar(
          message: 'Sale completed successfully!',
          type: AppSnackBarType.success,
        );
        context.go('/dashboard');
      }
    } else {
      final state = ref.read(scannerControllerProvider);
      if (context.mounted) {
        context.showAppSnackBar(
          message: state.message ?? 'Sale failed. Please try again.',
          type: AppSnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalItems = widget.queue.fold<int>(0, (sum, item) => sum + (item.quantity as int));

    return Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.appTextTertiary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Confirm Sale', style: AppTypography.h4.copyWith(color: context.appTextPrimary)),
                      Text(
                        '$totalItems item${totalItems == 1 ? '' : 's'} • ${widget.queue.length} product${widget.queue.length == 1 ? '' : 's'}',
                        style: AppTypography.bodySmall.copyWith(color: context.appTextSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Item breakdown
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.3,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.queue.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: context.appDivider),
                itemBuilder: (_, i) {
                  final item = widget.queue[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.product.name,
                            style: AppTypography.bodyMedium.copyWith(color: context.appTextPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '×${item.quantity}',
                          style: AppTypography.bodySmall.copyWith(color: context.appTextSecondary),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          Formatters.currency(item.lineTotal),
                          style: AppTypography.labelMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: context.appTextPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Total
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: context.isDark
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.primarySurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Amount',
                    style: AppTypography.labelLarge.copyWith(
                      color: context.isDark ? AppColors.primaryLight : AppColors.primaryDark,
                    ),
                  ),
                  Text(
                    Formatters.currency(widget.subtotal),
                    style: AppTypography.h3.copyWith(
                      color: context.isDark ? AppColors.primaryLight : AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Complete Sale button
            AppButton(
              label: _isProcessing ? 'Processing...' : 'Complete Sale',
              isLoading: _isProcessing,
              onPressed: _isProcessing ? null : _completeSale,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
