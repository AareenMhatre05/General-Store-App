import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// One column of the chart: a time bucket split by sales channel.
class SalesBucket {
  const SalesBucket({
    required this.label,
    required this.delivery,
    required this.inStore,
  });

  final String label;
  final double delivery;
  final double inStore;

  double get total => delivery + inStore;
}

/// Stacked bar chart of revenue per time bucket, split by channel.
///
/// Stacked rather than side-by-side because the question is "how much did
/// we take, and how was it split" -- the bar's full height answers the
/// first, the segments the second. Side-by-side would answer neither at a
/// glance.
///
/// Hand-drawn from plain widgets rather than a charting package: it is a
/// bar chart, the layout is a column of proportional heights, and every
/// extra Android dependency is another release-build risk.
class SalesBarChart extends StatefulWidget {
  const SalesBarChart({super.key, required this.buckets});

  final List<SalesBucket> buckets;

  @override
  State<SalesBarChart> createState() => _SalesBarChartState();
}

class _SalesBarChartState extends State<SalesBarChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final buckets = widget.buckets;
    final maxTotal = buckets.fold(0.0, (m, b) => b.total > m ? b.total : m);
    // A flat zero would divide by zero and draw nothing; give the axis a
    // nominal top so the empty state still renders a baseline.
    final axisTop = maxTotal <= 0 ? 1.0 : maxTotal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected-bar readout. Sits above the plot so tapping a bar
        // never covers the bar you tapped.
        SizedBox(
          height: 34,
          child: _selected == null
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tap a bar for its exact figures',
                    style: AppTextStyles.labelMd
                        .copyWith(color: context.colors.onSurfaceVariant),
                  ),
                )
              : _Readout(bucket: buckets[_selected!]),
        ),
        SizedBox(
          height: 170,
          child: Stack(
            children: [
              // Recessive gridlines: present for reading values off,
              // never competing with the data.
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    4,
                    (_) => Container(height: 1, color: context.colors.chartGrid),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < buckets.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(
                          () => _selected = _selected == i ? null : i,
                        ),
                        child: _Bar(
                          bucket: buckets[i],
                          axisTop: axisTop,
                          selected: _selected == i,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final bucket in buckets)
              Expanded(
                child: Text(
                  bucket.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: AppTextStyles.labelMd
                      .copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.bucket,
    required this.axisTop,
    required this.selected,
  });

  final SalesBucket bucket;
  final double axisTop;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final usable = constraints.maxHeight;
        final deliveryHeight = (bucket.delivery / axisTop) * usable;
        final inStoreHeight = (bucket.inStore / axisTop) * usable;

        return Padding(
          // Thin marks with breathing room, rather than fat bars meeting
          // each other.
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (inStoreHeight > 0)
                Container(
                  height: inStoreHeight,
                  decoration: BoxDecoration(
                    color: AppPalette.chartSeries2,
                    // Rounded data-end only on the top of the stack; the
                    // bottom stays square, anchored to the baseline.
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                    border: selected
                        ? Border.all(color: context.colors.onSurface, width: 1)
                        : null,
                  ),
                ),
              // 2px of surface between stacked segments so the boundary
              // reads even when the two colours abut.
              if (inStoreHeight > 0 && deliveryHeight > 0)
                const SizedBox(height: 2),
              if (deliveryHeight > 0)
                Container(
                  height: deliveryHeight,
                  decoration: BoxDecoration(
                    color: AppPalette.chartSeries1,
                    borderRadius: inStoreHeight > 0
                        ? null
                        : const BorderRadius.vertical(top: Radius.circular(4)),
                    border: selected
                        ? Border.all(color: context.colors.onSurface, width: 1)
                        : null,
                  ),
                ),
              // A visible stub for a bucket with no sales, so an empty
              // day reads as "nothing sold" rather than "no data".
              if (bucket.total <= 0)
                Container(
                  height: 2,
                  color: context.colors.chartGrid,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.bucket});

  final SalesBucket bucket;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(bucket.label, style: AppTextStyles.labelLg),
        const SizedBox(width: AppSpacing.base),
        Text(
          formatInr(bucket.total),
          style: AppTextStyles.labelLg.copyWith(color: context.colors.onSurface),
        ),
        const SizedBox(width: AppSpacing.base),
        Expanded(
          child: Text(
            '${formatInr(bucket.delivery)} delivery · '
            '${formatInr(bucket.inStore)} in-store',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelMd
                .copyWith(color: context.colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Legend for the two channels. Always shown, because identity must
/// never be carried by colour alone.
class SalesLegend extends StatelessWidget {
  const SalesLegend({
    super.key,
    required this.deliveryTotal,
    required this.inStoreTotal,
  });

  final double deliveryTotal;
  final double inStoreTotal;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LegendTile(
            color: AppPalette.chartSeries1,
            label: 'Delivery',
            value: deliveryTotal,
          ),
        ),
        const SizedBox(width: AppSpacing.base),
        Expanded(
          child: _LegendTile(
            color: AppPalette.chartSeries2,
            label: 'In-store',
            value: inStoreTotal,
          ),
        ),
      ],
    );
  }
}

class _LegendTile extends StatelessWidget {
  const _LegendTile({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base * 1.5),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              // The label carries identity; the swatch only reinforces it.
              Text(
                label,
                style: AppTextStyles.labelMd
                    .copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(formatInr(value), style: AppTextStyles.headlineSm),
        ],
      ),
    );
  }
}
