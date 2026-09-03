import 'package:flutter/material.dart';
import '../extensions/theme_ext.dart';

/// A sleek, overflow-proof badge indicating item synchronization status.
/// Designed to adapt seamlessly to both dark and light modes.
class PendingSyncBadge extends StatelessWidget {
  final String label;
  final bool compact;
  final Color? customColor;
  final IconData? customIcon;

  const PendingSyncBadge({
    super.key,
    this.label = 'Pending Sync',
    this.compact = false,
    this.customColor,
    this.customIcon,
  });

  const PendingSyncBadge.synced({
    super.key,
    this.label = 'Synced',
    this.compact = false,
  })  : customColor = const Color(0xFF16A34A),
        customIcon = Icons.check_circle_outline;

  const PendingSyncBadge.syncing({
    super.key,
    this.label = 'Syncing...',
    this.compact = false,
  })  : customColor = const Color(0xFF2563EB),
        customIcon = Icons.sync_rounded;

  const PendingSyncBadge.conflict({
    super.key,
    this.label = 'Conflict',
    this.compact = false,
  })  : customColor = const Color(0xFFDC2626),
        customIcon = Icons.warning_amber_rounded;

  const PendingSyncBadge.failed({
    super.key,
    this.label = 'Sync Failed',
    this.compact = false,
  })  : customColor = const Color(0xFFEA580C),
        customIcon = Icons.error_outline;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    final baseColor = customColor ??
        (isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100));

    final bgColor = isDark
        ? baseColor.withValues(alpha: 0.18)
        : baseColor.withValues(alpha: 0.12);

    final borderColor = isDark
        ? baseColor.withValues(alpha: 0.4)
        : baseColor.withValues(alpha: 0.35);

    final fgColor = baseColor;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: 1.5,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            customIcon ?? Icons.cloud_upload_outlined,
            size: compact ? 9.5 : 11,
            color: fgColor,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 8.5 : 9.5,
              fontWeight: FontWeight.w600,
              color: fgColor,
              letterSpacing: 0.1,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
