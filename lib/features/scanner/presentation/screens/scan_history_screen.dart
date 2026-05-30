import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/extensions/theme_ext.dart';
import '../../../../shared/models/scan_history_entry.dart';
import '../controllers/scanner_controller.dart';

/// Displays chronological scan history from Firestore
class ScanHistoryScreen extends ConsumerWidget {
  const ScanHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(scanHistoryProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appSurfaceRaised,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.appTextPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Scan History',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: context.appTextPrimary,
          ),
        ),
        centerTitle: false,
      ),
      body: historyAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 48, color: AppColors.error),
                const SizedBox(height: 16),
                Text('Failed to load scan history',
                    style: AppTypography.bodyLarge),
                const SizedBox(height: 8),
                Text(err.toString(),
                    style: AppTypography.bodySmall
                        .copyWith(color: context.appTextSecondary),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return _EmptyState();
          }

          // Group by date
          final grouped = <String, List<ScanHistoryEntry>>{};
          for (final entry in entries) {
            final key = _dateKey(entry.timestamp);
            grouped.putIfAbsent(key, () => []).add(entry);
          }

          final groupKeys = grouped.keys.toList();

          return ListView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.screenPaddingH,
              vertical: AppSizes.lg,
            ),
            itemCount: groupKeys.length,
            itemBuilder: (context, index) {
              final key = groupKeys[index];
              final items = grouped[key]!;
              final date = items.first.timestamp;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date header
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _friendlyDate(date),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.appTextSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          DateFormat('MMM d, yyyy')
                              .format(date)
                              .toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: context.appTextTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Entries
                  ...items.map((entry) => _ScanEntryTile(entry: entry)),
                  const SizedBox(height: 8),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _dateKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _friendlyDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(dt.year, dt.month, dt.day);

    if (dateOnly == today) return 'TODAY';
    if (dateOnly == today.subtract(const Duration(days: 1))) {
      return 'YESTERDAY';
    }
    return DateFormat('EEEE').format(dt).toUpperCase();
  }
}

// ═══════════════════════════════════════════════════════════════
// Scan Entry Tile
// ═══════════════════════════════════════════════════════════════

class _ScanEntryTile extends StatelessWidget {
  final ScanHistoryEntry entry;

  const _ScanEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isMatched = entry.isMatched;
    final statusColor = isMatched
        ? const Color(0xFF16A34A)
        : const Color(0xFFF59E0B);
    final statusBgColor = isMatched
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFFEF3C7);
    final intentLabel = entry.scanIntent == 'addProduct'
        ? 'Add Product'
        : 'Sale';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isMatched
                  ? Icons.check_circle_outline_rounded
                  : Icons.help_outline_rounded,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMatched
                      ? entry.matchedProductName ?? 'Product'
                      : 'Not Found',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  entry.barcodeValue,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Status + time
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                ),
                child: Text(
                  isMatched ? 'Matched' : 'Unmatched',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$intentLabel • ${DateFormat('hh:mm a').format(entry.timestamp)}',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Empty State
// ═══════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.appInputFill,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.qr_code_scanner_rounded,
                size: 36,
                color: context.appTextTertiary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No scans recorded yet',
              style: AppTypography.bodyLarge.copyWith(
                color: context.appTextSecondary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your scan history will appear here\nafter scanning barcodes.',
              style: AppTypography.bodySmall
                  .copyWith(color: context.appTextTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
