import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/extensions/theme_ext.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../transactions/presentation/controllers/transaction_logs_controller.dart';
import '../controllers/reporting_controller.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/constants/tax_policy.dart';
import '../controllers/annual_revenue_provider.dart';

/// Reporting screen driven by live Firestore data:
/// - Revenue + Units Sold header cards (from stock_movements)
/// - Sales Trends bar chart (last 7 days)
/// - Top Movers horizontal list (from actual sales)
/// - Recent Activity log (from stock_movements)
class ReportingScreen extends ConsumerWidget {
  const ReportingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revenue = ref.watch(reportRevenueProvider);
    final unitsSold = ref.watch(reportUnitsSoldProvider);
    final topMovers = ref.watch(topMoversProvider);
    final recentActivity = ref.watch(recentActivityProvider);
    final dailySales = ref.watch(dailySalesProvider);
    final movementsAsync = ref.watch(stockMovementsProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(title: const Text('Reporting')),
      body: movementsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text('Failed to load reports',
                  style: AppTypography.bodyMedium
                      .copyWith(color: context.appTextSecondary)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(stockMovementsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (_) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSizes.screenPaddingH),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Annual Revenue progress card (Nigeria Tax Act 2025) ──
              Consumer(
                builder: (context, ref, _) {
                  final annualRevenue = ref.watch(annualRevenueProvider);
                  final progress = (annualRevenue / TaxPolicy.smallCompanyTurnoverThreshold).clamp(0.0, 1.0);
                  final isOverThreshold = annualRevenue >= TaxPolicy.smallCompanyTurnoverThreshold;

                  return AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.account_balance_outlined,
                              color: isOverThreshold ? AppColors.error : AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: AppSizes.sm),
                            Text('Annual Revenue (${DateTime.now().year})',
                                style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: AppSizes.sm),
                        Text(Formatters.currency(annualRevenue),
                            style: AppTypography.h3.copyWith(
                              color: isOverThreshold ? AppColors.error : context.appTextPrimary,
                            )),
                        const SizedBox(height: AppSizes.sm),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: context.appDivider,
                            color: isOverThreshold ? AppColors.error : AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isOverThreshold
                              ? 'Exceeded the ₦100M small-company tax exemption threshold'
                              : '${Formatters.currency(TaxPolicy.smallCompanyTurnoverThreshold - annualRevenue)} below the ₦100M small-company threshold',
                          style: AppTypography.labelSmall.copyWith(
                            color: isOverThreshold ? AppColors.error : context.appTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSizes.lg),

              // ── Revenue Cards ──
              Row(
                children: [
                  Expanded(
                    child: _RevenueCard(
                      label: 'Revenue',
                      value: Formatters.currency(revenue),
                      hasData: revenue > 0,
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: _RevenueCard(
                      label: 'Units Sold',
                      value: Formatters.number(unitsSold),
                      hasData: unitsSold > 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.xxl),

              // ── Sales Trends Chart ──
              Text('Sales Trends (7 Days)', style: AppTypography.h4.copyWith(color: context.appTextPrimary)),
              const SizedBox(height: AppSizes.md),
              _SalesTrendsChart(dailySales: dailySales),
              const SizedBox(height: AppSizes.xxl),

              // ── Top Movers ──
              Text('Top Movers', style: AppTypography.h4.copyWith(color: context.appTextPrimary)),
              const SizedBox(height: AppSizes.md),
              if (topMovers.isEmpty)
                AppCard(
                  child: SizedBox(
                    height: 100,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.trending_up,
                              size: 28,
                              color: context.appTextTertiary
                                  .withValues(alpha: 0.5)),
                          const SizedBox(height: 8),
                          Text('No sales data yet',
                              style: AppTypography.bodySmall
                                  .copyWith(color: context.appTextTertiary)),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 130,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: topMovers.length,
                    itemBuilder: (context, index) {
                      final mover = topMovers[index];
                      return _TopMoverCard(
                        name: mover.name,
                        sold: mover.sold,
                        revenue: mover.revenue,
                        rank: index + 1,
                      );
                    },
                  ),
                ),
              const SizedBox(height: AppSizes.xxl),

              // ── Recent Activity ──
              Text('Recent Activity', style: AppTypography.h4.copyWith(color: context.appTextPrimary)),
              const SizedBox(height: AppSizes.md),
              if (recentActivity.isEmpty)
                AppCard(
                  child: SizedBox(
                    height: 100,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history,
                              size: 28,
                              color: context.appTextTertiary
                                  .withValues(alpha: 0.5)),
                          const SizedBox(height: 8),
                          Text('No recent activity',
                              style: AppTypography.bodySmall
                                  .copyWith(color: context.appTextTertiary)),
                        ],
                      ),
                    ),
                  ),
                )
              else
                ...recentActivity.map((a) => _ActivityItem(
                      icon: a.isIntake
                          ? Icons.inventory
                          : Icons.shopping_bag,
                      text:
                          '${a.isIntake ? "Restock" : "Sale"}: ${a.productName} x${a.quantity}',
                      time: Formatters.relative(a.timestamp),
                      color:
                          a.isIntake ? AppColors.info : AppColors.success,
                    )),
              const SizedBox(height: AppSizes.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Revenue Card ──
class _RevenueCard extends StatelessWidget {
  final String label;
  final String value;
  final bool hasData;

  const _RevenueCard({
    required this.label,
    required this.value,
    required this.hasData,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTypography.bodySmall
                  .copyWith(color: context.appTextSecondary)),
          const SizedBox(height: 4),
          Text(value, style: AppTypography.statMedium.copyWith(color: context.appTextPrimary)),
          const SizedBox(height: 4),
          if (hasData)
            Row(
              children: [
                const Icon(Icons.show_chart,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Text('Live data',
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.primary)),
              ],
            )
          else
            Row(
              children: [
                Icon(Icons.info_outline,
                    size: 14,
                    color: context.appTextTertiary.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Text('No data yet',
                    style: AppTypography.labelSmall
                        .copyWith(color: context.appTextTertiary)),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Sales Trends Bar Chart (last 7 days) ──
class _SalesTrendsChart extends StatelessWidget {
  final List<DailySales> dailySales;

  const _SalesTrendsChart({required this.dailySales});

  @override
  Widget build(BuildContext context) {
    final hasData = dailySales.any((d) => d.unitsSold > 0);

    return AppCard(
      child: SizedBox(
        height: 200,
        child: hasData
            ? BarChart(
                BarChartData(
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final day = dailySales[group.x.toInt()];
                        return BarTooltipItem(
                          '${day.unitsSold} units\n${Formatters.currency(day.revenue)}',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final index = v.toInt();
                          if (index < 0 || index >= dailySales.length) {
                            return const SizedBox.shrink();
                          }
                          final dayName = DateFormat('E')
                              .format(dailySales[index].date);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(dayName,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: context.appTextTertiary)),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  barGroups: List.generate(dailySales.length, (i) {
                    return BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: dailySales[i].unitsSold.toDouble(),
                        color: AppColors.primary,
                        width: 16,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ]);
                  }),
                ),
              )
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bar_chart_rounded,
                        size: 40,
                        color:
                            context.appTextTertiary.withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    Text('No sales in the last 7 days',
                        style: AppTypography.bodySmall
                            .copyWith(color: context.appTextTertiary)),
                    const SizedBox(height: 4),
                    Text(
                        'Sales data will appear here once transactions are recorded',
                        style: AppTypography.labelSmall
                            .copyWith(color: context.appTextTertiary),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
      ),
    );
  }
}

// ── Top Mover Card ──
class _TopMoverCard extends StatelessWidget {
  final String name;
  final int sold;
  final double revenue;
  final int rank;

  const _TopMoverCard({
    required this.name,
    required this.sold,
    required this.revenue,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 12),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '#$rank',
                      style: AppTypography.labelSmall
                          .copyWith(color: AppColors.primary),
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.trending_up,
                    size: 14, color: AppColors.success),
              ],
            ),
            const SizedBox(height: 8),
            Text(name,
                style: AppTypography.labelMedium.copyWith(color: context.appTextPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('$sold sold',
                style: AppTypography.bodySmall
                    .copyWith(color: context.appTextTertiary)),
            Text(Formatters.currency(revenue),
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}

// ── Activity Item ──
class _ActivityItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final String time;
  final Color color;

  const _ActivityItem({
    required this.icon,
    required this.text,
    required this.time,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: AppTypography.bodyMedium.copyWith(color: context.appTextPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          Text(time,
              style: AppTypography.bodySmall
                  .copyWith(color: context.appTextTertiary)),
        ],
      ),
    );
  }
}
