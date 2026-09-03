import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_typography.dart';
import '../sync/sync_models.dart';
import '../sync/sync_providers.dart';
import 'sync_operations_sheet.dart';

/// A global interactive banner displaying network & sync status.
/// Appears when offline, syncing, or when there are pending, failed, or conflicting changes.
/// Tapping opens the SyncOperationsSheet for full audit and resolution.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(syncStatusProvider);
    final pendingCount = ref.watch(pendingSyncCountProvider);
    final conflictCount = ref.watch(conflictSyncCountProvider);

    final status = statusAsync.value ?? SyncEngineState.idle;

    // Only show if offline, syncing, error, conflict, or if there are pending items
    final shouldShow = status == SyncEngineState.offline ||
        status == SyncEngineState.syncing ||
        status == SyncEngineState.error ||
        status == SyncEngineState.conflict ||
        status == SyncEngineState.waitingDependency ||
        status == SyncEngineState.retryWait ||
        pendingCount > 0;

    if (!shouldShow) return const SizedBox.shrink();

    Color bgColor;
    Color textColor;
    IconData icon;
    String message;

    switch (status) {
      case SyncEngineState.offline:
        bgColor = const Color(0xFFFFF3E0); // Light amber
        textColor = const Color(0xFFE65100);
        icon = Icons.cloud_off_rounded;
        message = pendingCount > 0
            ? 'Offline Mode • $pendingCount change${pendingCount > 1 ? 's' : ''} saved locally'
            : 'Offline Mode • Using local data';
        break;

      case SyncEngineState.syncing:
        bgColor = const Color(0xFFE3F2FD); // Light blue
        textColor = const Color(0xFF1565C0);
        icon = Icons.sync_rounded;
        message = 'Syncing $pendingCount change${pendingCount > 1 ? 's' : ''}...';
        break;

      case SyncEngineState.conflict:
        bgColor = const Color(0xFFFBE9E7); // Light deep orange
        textColor = const Color(0xFFD84315);
        icon = Icons.report_problem_rounded;
        message = conflictCount > 0
            ? '$conflictCount sync conflict${conflictCount > 1 ? 's' : ''} • Tap to resolve'
            : 'Sync conflict detected • Tap to review';
        break;

      case SyncEngineState.waitingDependency:
        bgColor = const Color(0xFFEDE7F6); // Light purple
        textColor = const Color(0xFF512DA8);
        icon = Icons.account_tree_rounded;
        message = 'Waiting on dependent changes to complete...';
        break;

      case SyncEngineState.retryWait:
        bgColor = const Color(0xFFFFF8E1); // Light amber
        textColor = const Color(0xFFF57F17);
        icon = Icons.replay_rounded;
        message = 'Retrying synchronization in background...';
        break;

      case SyncEngineState.error:
        bgColor = const Color(0xFFFFEBEE); // Light red
        textColor = const Color(0xFFC62828);
        icon = Icons.warning_amber_rounded;
        message = 'Sync issue • Tap to review ($pendingCount pending)';
        break;

      case SyncEngineState.idle:
        if (pendingCount > 0) {
          bgColor = const Color(0xFFFFF8E1);
          textColor = const Color(0xFFF57F17);
          icon = Icons.cloud_upload_outlined;
          message = '$pendingCount change${pendingCount > 1 ? 's' : ''} queued for sync';
        } else {
          return const SizedBox.shrink();
        }
        break;
    }

    return GestureDetector(
      onTap: () {
        SyncOperationsSheet.show(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: bgColor,
        child: SafeArea(
          bottom: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (status == SyncEngineState.syncing)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(textColor),
                  ),
                )
              else
                Icon(icon, size: 16, color: textColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  style: AppTypography.labelSmall.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: textColor.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
