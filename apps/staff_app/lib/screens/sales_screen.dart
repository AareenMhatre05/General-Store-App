import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../widgets/order_status_chip.dart';
import '../widgets/sales_bar_chart.dart';
import '../utils/sales_csv.dart';
import '../widgets/staff_scaffold.dart';

/// How the shop is doing, as distinct from the Orders queue, which is
/// what still needs doing.
///
/// Cancelled orders are excluded from every figure: they were restocked
/// and no money changed hands, so counting them would overstate takings.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

enum SalesPeriod {
  today('Today'),
  weekly('Weekly'),
  monthly('Monthly');

  const SalesPeriod(this.label);
  final String label;
}

class _SalesScreenState extends State<SalesScreen> {
  late final TableWatcher _watcher;
  late Future<List<StaffOrder>> _loadFuture;
  Future<SalesProfit>? _profitFuture;
  bool _isExporting = false;
  SalesPeriod _period = SalesPeriod.today;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
    // Revenue and the outstanding-cash figure both move without anyone
    // touching this screen: a counter sale rings up, or a delivery
    // partner records cash taken at the door.
    _watcher = TableWatcher(
      channelName: 'staff-sales',
      tables: const ['orders', 'order_items'],
      onChange: () {
        if (mounted) setState(() => _loadFuture = _load());
      },
    )..start();
  }

  @override
  void dispose() {
    _watcher.dispose();
    super.dispose();
  }

  DateTime get _startOfPeriod {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      SalesPeriod.today => startOfToday,
      SalesPeriod.weekly => startOfToday.subtract(const Duration(days: 6)),
      SalesPeriod.monthly => startOfToday.subtract(const Duration(days: 29)),
    };
  }

  Future<List<StaffOrder>> _load() {
    final repository = context.read<OrderRepository>();
    // Profit is computed server-side, from costs customers cannot read.
    _profitFuture = repository.getProfitBetween(
      from: _startOfPeriod,
      to: DateTime.now().add(const Duration(days: 1)),
    );
    return repository.getOrdersForStaff(createdAfter: _startOfPeriod);
  }

  /// Writes the report to a file and hands it to Android's share sheet,
  /// so it can go to Drive, email, WhatsApp or Files -- whatever the
  /// owner actually uses. Writing to a folder and hoping they find it is
  /// how exports get lost.
  Future<void> _exportCsv(List<StaffOrder> orders) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isExporting = true);
    try {
      final profit = await _profitFuture;
      final csv = buildSalesCsv(
        orders: orders,
        profit: profit,
        periodLabel: _period.label,
      );

      final stamp = DateTime.now();
      final name = 'KGS-sales-${_period.name}-'
          '${stamp.year}${stamp.month.toString().padLeft(2, '0')}'
          '${stamp.day.toString().padLeft(2, '0')}.csv';

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsString(csv);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'K.G.S sales report - ${_period.label}',
        text: 'Sales report for ${_period.label.toLowerCase()}.',
      );
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not create the report.')),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _selectPeriod(SalesPeriod period) {
    setState(() {
      _period = period;
      _loadFuture = _load();
    });
  }

  /// Buckets sized to the period so the chart always has a readable
  /// number of bars: 4-hour blocks across today, one bar per day for a
  /// week, one per week for a month (30 daily bars would be unreadable
  /// on a phone).
  List<SalesBucket> _bucket(List<StaffOrder> orders) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    double delivery(Iterable<StaffOrder> os) => os
        .where((o) => o.order.channel == OrderChannel.delivery)
        .fold(0.0, (sum, o) => sum + o.order.totalAmount);
    double inStore(Iterable<StaffOrder> os) => os
        .where((o) => o.order.channel == OrderChannel.inStore)
        .fold(0.0, (sum, o) => sum + o.order.totalAmount);

    switch (_period) {
      case SalesPeriod.today:
        return [
          for (var block = 0; block < 6; block++)
            () {
              final from = startOfToday.add(Duration(hours: block * 4));
              final to = from.add(const Duration(hours: 4));
              final inBlock = orders.where((o) {
                final at = o.order.createdAt.toLocal();
                return !at.isBefore(from) && at.isBefore(to);
              });
              return SalesBucket(
                label: DateFormat('ha').format(from).toLowerCase(),
                delivery: delivery(inBlock),
                inStore: inStore(inBlock),
              );
            }(),
        ];

      case SalesPeriod.weekly:
        return [
          for (var back = 6; back >= 0; back--)
            () {
              final day = startOfToday.subtract(Duration(days: back));
              final next = day.add(const Duration(days: 1));
              final onDay = orders.where((o) {
                final at = o.order.createdAt.toLocal();
                return !at.isBefore(day) && at.isBefore(next);
              });
              return SalesBucket(
                label: DateFormat('E').format(day).substring(0, 1),
                delivery: delivery(onDay),
                inStore: inStore(onDay),
              );
            }(),
        ];

      case SalesPeriod.monthly:
        return [
          for (var week = 4; week >= 0; week--)
            () {
              final from = startOfToday.subtract(Duration(days: week * 7 + 6));
              final to = from.add(const Duration(days: 7));
              final inWeek = orders.where((o) {
                final at = o.order.createdAt.toLocal();
                return !at.isBefore(from) && at.isBefore(to);
              });
              return SalesBucket(
                label: week == 0 ? 'This wk' : DateFormat('d MMM').format(from),
                delivery: delivery(inWeek),
                inStore: inStore(inWeek),
              );
            }(),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return StaffScaffold(
      currentIndex: 4,
      title: 'Sales',
      actions: [
        FutureBuilder<List<StaffOrder>>(
          future: _loadFuture,
          builder: (context, snapshot) => IconButton(
            tooltip: 'Download report',
            icon: _isExporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            onPressed: (snapshot.data == null || _isExporting)
                ? null
                : () => _exportCsv(snapshot.data!),
          ),
        ),
      ],
      body: FutureBuilder<List<StaffOrder>>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load sales.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }

          final all = snapshot.data ?? [];
          final counted =
              all.where((o) => o.order.status != OrderStatus.cancelled).toList();
          final deliveryTotal = counted
              .where((o) => o.order.channel == OrderChannel.delivery)
              .fold(0.0, (sum, o) => sum + o.order.totalAmount);
          final inStoreTotal = counted
              .where((o) => o.order.channel == OrderChannel.inStore)
              .fold(0.0, (sum, o) => sum + o.order.totalAmount);
          final revenue = deliveryTotal + inStoreTotal;
          final unpaid = counted
              .where((o) => o.order.paymentStatus != PaymentStatus.paid)
              .fold(0.0, (sum, o) => sum + o.order.totalAmount);

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _loadFuture = _load());
              await _loadFuture;
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
              children: [
                // Filters in one row above the charts.
                Row(
                  children: [
                    for (final period in SalesPeriod.values)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.base),
                          child: ChoiceChip(
                            label: SizedBox(
                              width: double.infinity,
                              child: Text(period.label, textAlign: TextAlign.center),
                            ),
                            selected: _period == period,
                            onSelected: (_) => _selectPeriod(period),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.gutter),

                // The headline is a number, not a chart -- one figure
                // answering "how much did we take" needs no plot.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                  decoration: BoxDecoration(
                    color: context.colors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total sales · ${_period.label.toLowerCase()}',
                        style: AppTextStyles.labelMd
                            .copyWith(color: context.colors.onPrimaryContainer),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatInr(revenue),
                        style: AppTextStyles.headlineLg
                            .copyWith(color: context.colors.onPrimaryContainer),
                      ),
                      Text(
                        '${counted.length} order${counted.length == 1 ? '' : 's'}',
                        style: AppTextStyles.bodySm
                            .copyWith(color: context.colors.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.base),

                _ProfitCard(future: _profitFuture),
                const SizedBox(height: AppSpacing.base),

                SalesLegend(
                  deliveryTotal: deliveryTotal,
                  inStoreTotal: inStoreTotal,
                ),
                if (unpaid > 0) ...[
                  const SizedBox(height: AppSpacing.base),
                  Row(
                    children: [
                      Icon(Icons.error_outline, size: 18, color: context.colors.error),
                      const SizedBox(width: AppSpacing.base),
                      Text(
                        '${formatInr(unpaid)} still to collect',
                        style: AppTextStyles.bodySm.copyWith(color: context.colors.error),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.gutter),

                Container(
                  padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: context.colors.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        switch (_period) {
                          SalesPeriod.today => 'Through the day',
                          SalesPeriod.weekly => 'Day by day',
                          SalesPeriod.monthly => 'Week by week',
                        },
                        style: AppTextStyles.headlineSm,
                      ),
                      const SizedBox(height: AppSpacing.base),
                      SalesBarChart(buckets: _bucket(counted)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.gutter),

                Text('Orders in this period', style: AppTextStyles.headlineSm),
                const SizedBox(height: AppSpacing.base),
                if (all.isEmpty)
                  Text(
                    'No orders in this period.',
                    style: AppTextStyles.bodyMd
                        .copyWith(color: context.colors.onSurfaceVariant),
                  )
                else
                  for (final staffOrder in all)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.base),
                      child: InkWell(
                        onTap: () => context.push('/orders/${staffOrder.order.id}'),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.base * 1.5),
                          decoration: BoxDecoration(
                            color: context.colors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: context.colors.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: staffOrder.order.channel == OrderChannel.inStore
                                      ? AppPalette.chartSeries2
                                      : AppPalette.chartSeries1,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.base),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(staffOrder.customerLabel,
                                        style: AppTextStyles.labelLg),
                                    Text(
                                      DateFormat('d MMM, h:mm a')
                                          .format(staffOrder.order.createdAt.toLocal()),
                                      style: AppTextStyles.bodySm
                                          .copyWith(color: context.colors.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              OrderStatusChip(
                                  status: staffOrder.order.status, compact: true),
                              const SizedBox(width: AppSpacing.base),
                              Text(formatInr(staffOrder.order.totalAmount),
                                  style: AppTextStyles.priceDisplay),
                            ],
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Revenue minus supplier cost for the period.
///
/// Separate from the revenue headline because they answer different
/// questions -- "how much came in" versus "how much we kept" -- and
/// conflating them makes a busy day on thin margins look like a good one.
class _ProfitCard extends StatelessWidget {
  const _ProfitCard({required this.future});

  final Future<SalesProfit>? future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SalesProfit>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 76);
        }
        if (snapshot.hasError || !snapshot.hasData) return const SizedBox.shrink();

        final profit = snapshot.data!;
        final losing = profit.profit < 0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: losing ? context.colors.error : context.colors.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    losing ? Icons.trending_down : Icons.savings_outlined,
                    size: 18,
                    color: losing ? context.colors.error : context.colors.success,
                  ),
                  const SizedBox(width: AppSpacing.base),
                  Text('Profit', style: AppTextStyles.labelLg),
                  const Spacer(),
                  Text(
                    '${profit.marginPercent.toStringAsFixed(0)}% margin',
                    style: AppTextStyles.labelMd
                        .copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                formatInr(profit.profit),
                style: AppTextStyles.headlineMd.copyWith(
                  color: losing ? context.colors.error : context.colors.success,
                ),
              ),
              Text(
                'Sold ${formatInr(profit.revenue)} - cost ${formatInr(profit.cost)}',
                style: AppTextStyles.bodySm
                    .copyWith(color: context.colors.onSurfaceVariant),
              ),
              // An honest caveat beats a confident wrong number: items
              // with no cost recorded count as pure profit.
              if (profit.isIncomplete) ...[
                const SizedBox(height: AppSpacing.base),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: context.colors.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${profit.uncostedItems} sold item(s) have no cost price set, '
                        'so this is higher than the real figure.',
                        style: AppTextStyles.labelMd.copyWith(color: context.colors.error),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
