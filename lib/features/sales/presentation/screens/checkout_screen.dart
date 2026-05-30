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
/// Checkout screen — payment method selection and confirmation

/// Checkout screen — payment method selection and confirmation
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _paymentMethod = 'cash';
  bool _isProcessing = false;

  final _methods = [
    {'id': 'cash', 'label': 'Cash', 'icon': Icons.money_rounded},
    {'id': 'card', 'label': 'Card', 'icon': Icons.credit_card_rounded},
    {'id': 'transfer', 'label': 'Transfer', 'icon': Icons.account_balance_rounded},
    {'id': 'mobile', 'label': 'Mobile Pay', 'icon': Icons.phone_android_rounded},
  ];

  Future<void> _processPayment() async {
    setState(() => _isProcessing = true);

    // In production, this calls the validateStockDeduction Cloud Function
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    setState(() => _isProcessing = false);

    // No cart needed anymore for checkout


    // Show receipt
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
              const SizedBox(width: 8),
              Text('Sale Complete!', style: AppTypography.h4),
            ],
          ),
          content: Text(
            'Transaction processed successfully via ${_paymentMethod.toUpperCase()}.',
            style: AppTypography.bodyMedium,
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/dashboard');
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = <dynamic>[];
    final subtotal = 0.0;
    final discount = 0.0;
    final total = 0.0;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text('Checkout'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.screenPaddingH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Summary
            Text('Order Summary', style: AppTypography.h4),
            const SizedBox(height: AppSizes.md),
            AppCard(
              child: Column(
                children: [
                  ...cartItems.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('${item.product.name} x${item.quantity}',
                                  style: AppTypography.bodyMedium),
                            ),
                            Text(Formatters.currency(item.totalPrice),
                                style: AppTypography.labelMedium),
                          ],
                        ),
                      )),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Subtotal', style: AppTypography.bodyMedium.copyWith(color: context.appTextSecondary)),
                      Text(Formatters.currency(subtotal), style: AppTypography.labelMedium),
                    ],
                  ),
                  if (discount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Discount', style: AppTypography.bodyMedium.copyWith(color: AppColors.success)),
                        Text('-${Formatters.currency(discount)}', style: AppTypography.labelMedium.copyWith(color: AppColors.success)),
                      ],
                    ),
                  ],
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total', style: AppTypography.h4),
                      Text(Formatters.currency(total), style: AppTypography.h3.copyWith(color: AppColors.primary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.xxl),

            // Payment Method
            Text('Payment Method', style: AppTypography.h4),
            const SizedBox(height: AppSizes.md),
            ...(_methods.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _paymentMethod = m['id'] as String),
                    child: AppCard(
                      border: Border.all(
                        color: _paymentMethod == m['id']
                            ? AppColors.primary
                            : AppColors.cardBorder,
                        width: _paymentMethod == m['id'] ? 2 : 1,
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: _paymentMethod == m['id']
                                  ? AppColors.primarySurface
                                  : AppColors.inputFill,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(m['icon'] as IconData,
                                color: _paymentMethod == m['id'] ? AppColors.primary : context.appTextTertiary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Text(m['label'] as String, style: AppTypography.labelLarge),
                          const Spacer(),
                          if (_paymentMethod == m['id'])
                            const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 22),
                        ],
                      ),
                    ),
                  ),
                ))),
            const SizedBox(height: AppSizes.xxxl),

            AppButton(
              label: 'Confirm Payment — ${Formatters.currency(total)}',
              isLoading: _isProcessing,
              onPressed: _processPayment,
            ),
            const SizedBox(height: AppSizes.xxl),
          ],
        ),
      ),
    );
  }
}
