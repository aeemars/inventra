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

class SalesQueueScreen extends ConsumerWidget {
  const SalesQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(salesQueueProvider);
    final subtotal = ref.watch(salesQueueSubtotalProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text('Review Sale'),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                return AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.product.name,
                              style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
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
                      ),
                      Text('${item.quantity}', style: AppTypography.bodyMedium),
                      IconButton(
                        onPressed: () => ref
                            .read(salesQueueProvider.notifier)
                            .updateQuantity(item.product.id, item.quantity + 1),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSizes.sm),
                      SizedBox(
                        width: 80,
                        child: Text(
                          Formatters.currency(item.lineTotal),
                          textAlign: TextAlign.right,
                          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        onPressed: () => ref
                            .read(salesQueueProvider.notifier)
                            .removeItem(item.product.id),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: AppColors.error,
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
                        Text('Total', style: AppTypography.h4),
                        Text(
                          Formatters.currency(subtotal),
                          style: AppTypography.h4.copyWith(color: AppColors.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.md),
                    AppButton(
                      label: 'Complete Sale',
                      onPressed: () async {
                        final success = await ref
                            .read(scannerControllerProvider.notifier)
                            .completeMultiItemSale(queue);
                        if (success) {
                          ref.read(salesQueueProvider.notifier).clear();
                          if (context.mounted) context.go('/dashboard');
                        } else if (context.mounted) {
                          final state = ref.read(scannerControllerProvider);
                          context.showAppSnackBar(
                            message: state.message ?? 'Sale failed',
                            type: AppSnackBarType.error,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
