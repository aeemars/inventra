import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import '../sync/sync_models.dart';
import '../sync/sync_providers.dart';

/// Interactive modal sheet displaying active, pending, failed, and conflicted sync operations.
/// Allows users to view audit details, manually trigger retries, or safely void rejected transactions.
class SyncOperationsSheet extends ConsumerStatefulWidget {
  const SyncOperationsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const SyncOperationsSheet(),
    );
  }

  @override
  ConsumerState<SyncOperationsSheet> createState() => _SyncOperationsSheetState();
}

class _SyncOperationsSheetState extends ConsumerState<SyncOperationsSheet> {
  String _selectedFilter = 'all'; // 'all', 'pending', 'conflicts', 'failed'

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final queueItemsAsync = ref.watch(syncQueueItemsProvider);
    final syncProcessor = ref.watch(syncProcessorProvider);
    final syncStatusAsync = ref.watch(syncStatusProvider);
    final engineState = syncStatusAsync.value ?? SyncEngineState.idle;

    final allItems = queueItemsAsync.value ?? [];
    final pendingItems = allItems
        .where((i) => i.status == SyncStatus.pending || i.status == SyncStatus.processing)
        .toList();
    final conflictItems =
        allItems.where((i) => i.status == SyncStatus.conflict).toList();
    final failedItems =
        allItems.where((i) => i.status == SyncStatus.failed).toList();

    List<SyncQueueItem> displayedItems;
    switch (_selectedFilter) {
      case 'pending':
        displayedItems = pendingItems;
        break;
      case 'conflicts':
        displayedItems = conflictItems;
        break;
      case 'failed':
        displayedItems = failedItems;
        break;
      default:
        displayedItems = allItems;
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.sync_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sync Operations',
                        style: AppTypography.h4.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        '${allItems.length} total operations in local queue',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: engineState == SyncEngineState.syncing
                      ? null
                      : () => syncProcessor.processQueue(),
                  icon: engineState == SyncEngineState.syncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Sync Now'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Filter bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _buildFilterChip('All (${allItems.length})', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Pending (${pendingItems.length})', 'pending'),
                const SizedBox(width: 8),
                _buildFilterChip('Conflicts (${conflictItems.length})', 'conflicts',
                    isWarning: conflictItems.isNotEmpty),
                const SizedBox(width: 8),
                _buildFilterChip('Failed (${failedItems.length})', 'failed',
                    isError: failedItems.isNotEmpty),
              ],
            ),
          ),

          // Operations List
          Expanded(
            child: displayedItems.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: displayedItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = displayedItems[index];
                      return _OperationCard(item: item);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String key,
      {bool isWarning = false, bool isError = false}) {
    final isSelected = _selectedFilter == key;
    Color chipColor = isSelected ? AppColors.primary : Colors.transparent;
    Color textColor = isSelected ? Colors.white : Colors.black87;

    if (isWarning && !isSelected) {
      textColor = const Color(0xFFE65100);
    } else if (isError && !isSelected) {
      textColor = const Color(0xFFC62828);
    }

    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: chipColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (isError
                    ? Colors.red.withValues(alpha: 0.4)
                    : (isWarning
                        ? Colors.orange.withValues(alpha: 0.4)
                        : Colors.grey.withValues(alpha: 0.3))),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: textColor,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_done_rounded,
            size: 48,
            color: Colors.green.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 12),
          Text(
            'Queue is clear',
            style: AppTypography.labelLarge.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'All local changes are fully synchronized.',
            style: AppTypography.bodySmall.copyWith(
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationCard extends ConsumerWidget {
  final SyncQueueItem item;

  const _OperationCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final syncProcessor = ref.watch(syncProcessorProvider);

    final isConflict = item.status == SyncStatus.conflict;
    final isFailed = item.status == SyncStatus.failed;
    final isProcessing = item.status == SyncStatus.processing;

    Color borderColor;
    if (isConflict) {
      borderColor = const Color(0xFFFFA000); // Amber/orange
    } else if (isFailed) {
      borderColor = const Color(0xFFE53935); // Red
    } else {
      borderColor = isDark ? Colors.white12 : Colors.black12;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF262638) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: isConflict || isFailed ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row: Icon, Title, Status Chip
          Row(
            children: [
              _buildOpIcon(item.operationType),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _opDisplayName(item.operationType),
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      'Entity ID: ${item.entityId ?? item.localId}',
                      style: AppTypography.labelSmall.copyWith(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(item),
            ],
          ),

          // Dependencies notice if applicable
          if (item.allDependencies.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 13,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Depends on ${item.allDependencies.length} operation(s)',
                    style: AppTypography.labelSmall.copyWith(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // Conflict / Failure details container
          if (isConflict || isFailed) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isConflict
                    ? const Color(0xFFFFF8E1)
                    : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.conflictCategory != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        item.conflictCategory!.label,
                        style: AppTypography.labelSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isConflict
                              ? const Color(0xFFE65100)
                              : const Color(0xFFC62828),
                        ),
                      ),
                    ),
                  Text(
                    item.conflictExplanation ??
                        item.lastError ??
                        'An unexpected conflict occurred.',
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 12,
                      color: isConflict
                          ? const Color(0xFFBF360C)
                          : const Color(0xFFB71C1C),
                    ),
                  ),
                ],
              ),
            ),

            // Action row
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (item.operationType == SyncOperationType.createSale) ...[
                  OutlinedButton.icon(
                    onPressed: () => _confirmVoidSale(context, ref, item),
                    icon: const Icon(Icons.cancel_outlined, size: 14),
                    label: const Text('Void Sale'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.redAccent),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton.icon(
                  onPressed: isProcessing
                      ? null
                      : () => syncProcessor.retryOperation(item.localId),
                  icon: const Icon(Icons.replay_rounded, size: 14),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _confirmVoidSale(
      BuildContext context, WidgetRef ref, SyncQueueItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void Conflicted Sale?'),
        content: const Text(
          'This will cancel the offline transaction record and remove it from the synchronization queue. This action is auditable and non-reversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(syncProcessorProvider).voidOperation(item.localId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Void Transaction'),
          ),
        ],
      ),
    );
  }

  Widget _buildOpIcon(SyncOperationType type) {
    IconData icon;
    Color color;

    switch (type) {
      case SyncOperationType.createSale:
        icon = Icons.shopping_cart_rounded;
        color = const Color(0xFF2E7D32); // Green
        break;
      case SyncOperationType.createProduct:
        icon = Icons.add_box_rounded;
        color = const Color(0xFF1565C0); // Blue
        break;
      case SyncOperationType.updateProduct:
        icon = Icons.edit_note_rounded;
        color = const Color(0xFF00838F); // Cyan
        break;
      case SyncOperationType.deleteProduct:
        icon = Icons.delete_outline_rounded;
        color = const Color(0xFFC62828); // Red
        break;
      case SyncOperationType.restock:
        icon = Icons.trending_up_rounded;
        color = const Color(0xFF6A1B9A); // Purple
        break;
      case SyncOperationType.stockAdjustment:
        icon = Icons.tune_rounded;
        color = const Color(0xFFEF6C00); // Orange
        break;
      case SyncOperationType.createScan:
        icon = Icons.qr_code_scanner_rounded;
        color = const Color(0xFF00695C); // Teal
        break;
      default:
        icon = Icons.sync_rounded;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  Widget _buildStatusBadge(SyncQueueItem item) {
    Color bg;
    Color fg;
    String label;

    switch (item.status) {
      case SyncStatus.pending:
        bg = const Color(0xFFE0E0E0);
        fg = const Color(0xFF424242);
        label = item.retryCount > 0 ? 'Retry #${item.retryCount}' : 'Pending';
        break;
      case SyncStatus.processing:
        bg = const Color(0xFFE3F2FD);
        fg = const Color(0xFF1565C0);
        label = 'Syncing...';
        break;
      case SyncStatus.synced:
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        label = 'Synced';
        break;
      case SyncStatus.conflict:
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFE65100);
        label = item.conflictCategory != null
            ? item.conflictCategory!.label
            : 'Conflict';
        break;
      case SyncStatus.failed:
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFC62828);
        label = 'Failed';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  String _opDisplayName(SyncOperationType type) {
    switch (type) {
      case SyncOperationType.createProduct:
        return 'Create Product';
      case SyncOperationType.updateProduct:
        return 'Update Product';
      case SyncOperationType.deleteProduct:
        return 'Deactivate Product';
      case SyncOperationType.createSale:
        return 'Point of Sale';
      case SyncOperationType.restock:
        return 'Restock';
      case SyncOperationType.stockAdjustment:
        return 'Stock Adjustment';
      case SyncOperationType.createScan:
        return 'Scan Record';
      case SyncOperationType.createCategory:
        return 'Create Category';
      case SyncOperationType.updateCategory:
        return 'Update Category';
      case SyncOperationType.deleteCategory:
        return 'Delete Category';
    }
  }
}
