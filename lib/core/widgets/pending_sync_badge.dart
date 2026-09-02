import 'package:flutter/material.dart';
import '../extensions/theme_ext.dart';

/// A sleek, overflow-proof badge indicating a local item is pending synchronization.
/// Designed to adapt seamlessly to both dark and light modes.
class PendingSyncBadge extends StatelessWidget {
  final String label;
  final bool compact;

  const PendingSyncBadge({
    super.key,
    this.label = 'Pending Sync',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    final bgColor = isDark
        ? const Color(0xFF2E1C07)
        : const Color(0xFFFFF3E0);

    final borderColor = isDark
        ? const Color(0x66FFA726)
        : const Color(0xFFFFB74D);

    final fgColor = isDark
        ? const Color(0xFFFFB74D)
        : const Color(0xFFE65100);

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
            Icons.cloud_upload_outlined,
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
