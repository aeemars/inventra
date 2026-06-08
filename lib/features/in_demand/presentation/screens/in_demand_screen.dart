import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/theme_ext.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../shared/providers/firebase_providers.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';

class InDemandScreen extends ConsumerStatefulWidget {
  const InDemandScreen({super.key});

  @override
  ConsumerState<InDemandScreen> createState() => _InDemandScreenState();
}

class _InDemandScreenState extends ConsumerState<InDemandScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    if (!_formKey.currentState!.validate()) return;

    final shopId = ref.read(currentShopIdProvider);
    final authState = ref.read(authStateProvider);
    final uid = authState.value?.uid;

    if (shopId == null || uid == null) {
      _showSnack('Unable to add item. Please try again.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final firestore = ref.read(firestoreProvider);
      await firestore
          .collection('shops')
          .doc(shopId)
          .collection('in_demand')
          .add({
        'name': _nameController.text.trim(),
        'note': _noteController.text.trim(),
        'requestCount': 1,
        'createdAt': Timestamp.now(),
        'addedBy': uid,
      });

      _nameController.clear();
      _noteController.clear();
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(InDemandFailure.addFailed().message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _incrementRequest(
    DocumentReference<Map<String, dynamic>> docRef,
  ) async {
    try {
      await docRef.update({'requestCount': FieldValue.increment(1)});
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(InDemandFailure.incrementFailed().message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shopId = ref.read(currentShopIdProvider);
    final firestore = ref.read(firestoreProvider);

    final inDemandCollection = shopId == null
        ? null
        : firestore.collection('shops').doc(shopId).collection('in_demand');

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text('In-Demand Items'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.screenPaddingH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Item', style: AppTypography.h4.copyWith(color: context.appTextPrimary)),
            const SizedBox(height: AppSizes.md),
            AppCard(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTextField(
                      label: 'Item Name',
                      hint: 'e.g. Cold brew coffee',
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Item name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSizes.lg),
                    AppTextField(
                      label: 'Note (optional)',
                      hint: 'Add any specifics or details',
                      controller: _noteController,
                      maxLines: 3,
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: AppSizes.lg),
                    AppButton(
                      label: 'Add to List',
                      isLoading: _isSubmitting,
                      backgroundColor: AppColors.coral,
                      onPressed: _isSubmitting ? null : _addItem,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSizes.xxl),
            Text('Requested Items', style: AppTypography.h4.copyWith(color: context.appTextPrimary)),
            const SizedBox(height: AppSizes.md),
            if (inDemandCollection == null)
              _EmptyState(
                icon: Icons.storefront_outlined,
                message: 'Shop not available.',
              )
            else
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: inDemandCollection
                    .orderBy('requestCount', descending: true)
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return _EmptyState(
                      icon: Icons.error_outline,
                      message: 'Failed to load items.',
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return const _EmptyState(
                      icon: Icons.inbox_outlined,
                      message: 'No in-demand items yet.',
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data();
                      final name = (data['name'] as String?) ?? '';
                      final note = (data['note'] as String?) ?? '';
                      final requestCount =
                          (data['requestCount'] as num?)?.toInt() ?? 0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSizes.md),
                        child: _InDemandItemCard(
                          name: name,
                          note: note,
                          requestCount: requestCount,
                          onIncrement: () => _incrementRequest(doc.reference),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _InDemandItemCard extends StatelessWidget {
  final String name;
  final String note;
  final int requestCount;
  final VoidCallback onIncrement;

  const _InDemandItemCard({
    required this.name,
    required this.note,
    required this.requestCount,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Unnamed item' : name,
                  style: AppTypography.bodyLarge.copyWith(color: context.appTextPrimary),
                ),
                if (note.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSizes.xs),
                  Text(
                    note,
                    style: AppTypography.bodySmall
                        .copyWith(color: context.appTextSecondary),
                  ),
                ],
                const SizedBox(height: AppSizes.md),
                _RequestBadge(count: requestCount),
              ],
            ),
          ),
          IconButton(
            onPressed: onIncrement,
            icon: const Icon(
              Icons.exposure_plus_1_rounded,
              color: AppColors.coral,
            ),
            tooltip: 'Add request',
          ),
        ],
      ),
    );
  }
}

class _RequestBadge extends StatelessWidget {
  final int count;

  const _RequestBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.coral.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusFull),
      ),
      child: Text(
        '$count requests',
        style: AppTypography.labelMedium.copyWith(color: AppColors.coral),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.xxl),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSizes.iconXxl, color: context.appTextTertiary),
          const SizedBox(height: AppSizes.sm),
          Text(
            message,
            style: AppTypography.bodyMedium
                .copyWith(color: context.appTextSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
