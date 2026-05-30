import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/extensions/theme_ext.dart';
import '../controllers/transaction_logs_controller.dart';

/// Transaction Logs screen matching the Figma reference:
/// - AppBar with back arrow + filter icon
/// - Two summary cards (Intake / Sales)
/// - Grouped transaction list by date
class TransactionLogsScreen extends ConsumerWidget {
  const TransactionLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(stockMovementsProvider);
    final filteredLogs = ref.watch(filteredTransactionLogsProvider);
    final intakeToday = ref.watch(todayIntakeCountProvider);
    final salesToday = ref.watch(todaySalesCountProvider);
    final currentFilter = ref.watch(transactionFilterProvider);

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
          'Transaction Logs',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: context.appTextPrimary,
          ),
        ),
        centerTitle: false,
        actions: [
          PopupMenuButton<TransactionFilter>(
            icon: Icon(Icons.filter_list_rounded,
                color: context.appTextPrimary),
            onSelected: (filter) {
              ref.read(transactionFilterProvider.notifier).state = filter;
            },
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            itemBuilder: (_) => [
              _filterMenuItem(
                'All Transactions',
                TransactionFilter.all,
                currentFilter,
              ),
              _filterMenuItem(
                'Intake Only',
                TransactionFilter.intake,
                currentFilter,
              ),
              _filterMenuItem(
                'Sales Only',
                TransactionFilter.sales,
                currentFilter,
              ),
            ],
          ),
        ],
      ),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 48, color: AppColors.error),
                const SizedBox(height: 16),
                Text('Failed to load transactions',
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
        data: (_) => Column(
          children: [
            Divider(height: 1, color: context.appDivider),

            // ── Summary Cards ──
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.screenPaddingH,
                AppSizes.xl,
                AppSizes.screenPaddingH,
                AppSizes.lg,
              ),
              child: Row(
                children: [
                  // Intake card
                  Expanded(
                    child: _SummaryCard(
                      label: 'INTAKE',
                      value: intakeToday,
                      subtitle: 'Items added today',
                      color: const Color(0xFF2E7D32),
                      bgColor: const Color(0xFFE8F5E9),
                      icon: Icons.arrow_downward_rounded,
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  // Sales card
                  Expanded(
                    child: _SummaryCard(
                      label: 'SALES',
                      value: salesToday,
                      subtitle: 'Items sold today',
                      color: const Color(0xFFE85D3A),
                      bgColor: const Color(0xFFFFF3E0),
                      icon: Icons.arrow_upward_rounded,
                    ),
                  ),
                ],
              ),
            ),

            // ── Transaction List ──
            Expanded(
              child: filteredLogs.isEmpty
                  ? _EmptyState(filter: currentFilter)
                  : _TransactionList(logs: filteredLogs),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<TransactionFilter> _filterMenuItem(
    String label,
    TransactionFilter value,
    TransactionFilter current,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (value == current)
            const Icon(Icons.check, size: 18, color: AppColors.primary)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text(label, style: AppTypography.bodyMedium),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Summary Card
// ═══════════════════════════════════════════════════════════════
class _SummaryCard extends StatelessWidget {
  final String label;
  final int value;
  final String subtitle;
  final Color color;
  final Color bgColor;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = context.isDark ? context.appSurface : bgColor;
    final valueColor = context.isDark ? context.appTextPrimary : AppColors.textPrimary;
    final subtitleColor = context.isDark ? context.appTextSecondary : AppColors.textSecondary;
    final cardBorder = context.isDark ? Border.all(color: context.appCardBorder) : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row with icon
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Large number
          Text(
            '$value',
            style: GoogleFonts.inter(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: valueColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          // Subtitle
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: subtitleColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Transaction List (grouped by date)
// ═══════════════════════════════════════════════════════════════
class _TransactionList extends StatelessWidget {
  final List<TransactionLogEntry> logs;

  const _TransactionList({required this.logs});

  @override
  Widget build(BuildContext context) {
    // Group logs by date
    final grouped = <String, List<TransactionLogEntry>>{};
    for (final log in logs) {
      final key = _dateGroupKey(log.createdAt);
      grouped.putIfAbsent(key, () => []).add(log);
    }

    final groupKeys = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.screenPaddingH,
      ),
      itemCount: groupKeys.length,
      itemBuilder: (context, index) {
        final key = groupKeys[index];
        final items = grouped[key]!;
        final date = items.first.createdAt;

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
                    _friendlyDateLabel(date),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    DateFormat('MMM d, yyyy').format(date).toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: context.appTextTertiary,
                    ),
                  ),
                ],
              ),
            ),
            // Transaction items
            ...items.map((log) => _TransactionTile(entry: log)),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  String _dateGroupKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _friendlyDateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(dt.year, dt.month, dt.day);

    if (dateOnly == today) return 'TODAY';
    if (dateOnly == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
    return DateFormat('EEEE').format(dt).toUpperCase();
  }
}

// ═══════════════════════════════════════════════════════════════
// Transaction Tile
// ═══════════════════════════════════════════════════════════════
class _TransactionTile extends StatelessWidget {
  final TransactionLogEntry entry;

  const _TransactionTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isPositive = entry.quantityChange > 0;
    final changeColor = isPositive
        ? const Color(0xFF16A34A) // green
        : const Color(0xFFDC2626); // red
    final iconBgColor = context.isDark
        ? (isPositive ? const Color(0xFF16A34A).withValues(alpha: 0.15) : const Color(0xFFDC2626).withValues(alpha: 0.15))
        : (isPositive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2));
    final iconColor = isPositive
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);

    final changeText = isPositive
        ? '+ ${entry.quantityChange}'
        : '- ${entry.quantityChange.abs()}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: context.appCardBorder),
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
          // Icon circle
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPositive ? Icons.add : Icons.remove,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),

          // Product info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.productName,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${entry.typeLabel} • ID #${entry.referenceId}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: context.appTextSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Quantity change + time
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                changeText,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: changeColor,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                DateFormat('hh:mm a').format(entry.createdAt),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: context.appTextTertiary,
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
  final TransactionFilter filter;

  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      TransactionFilter.all => 'No transactions recorded yet',
      TransactionFilter.intake => 'No intake transactions found',
      TransactionFilter.sales => 'No sales transactions found',
    };

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
                Icons.receipt_long_outlined,
                size: 36,
                color: context.appTextTertiary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: AppTypography.bodyLarge.copyWith(
                color: context.appTextSecondary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Transaction logs will appear here\nafter scanning products.',
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
