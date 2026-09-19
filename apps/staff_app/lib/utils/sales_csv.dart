import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

/// Builds the sales report as CSV.
///
/// CSV rather than a real .xlsx file: every spreadsheet program opens it
/// (Excel, Google Sheets, LibreOffice), it survives being emailed or sent
/// over WhatsApp, and it needs no Android library to produce. An .xlsx
/// would look marginally nicer and cost a dependency plus a whole file
/// format to get wrong.
String buildSalesCsv({
  required List<StaffOrder> orders,
  required SalesProfit? profit,
  required String periodLabel,
}) {
  final buffer = StringBuffer();
  final date = DateFormat('yyyy-MM-dd HH:mm');

  // A short header block, so the file still makes sense months later
  // when nobody remembers which period it covered.
  buffer.writeln(_row(['Kavita General Stores - Sales Report']));
  buffer.writeln(_row(['Period', periodLabel]));
  buffer.writeln(_row(['Generated', date.format(DateTime.now())]));
  buffer.writeln();

  final counted =
      orders.where((o) => o.order.status != OrderStatus.cancelled).toList();
  final revenue = counted.fold(0.0, (sum, o) => sum + o.order.totalAmount);
  final delivery = counted
      .where((o) => o.order.channel == OrderChannel.delivery)
      .fold(0.0, (sum, o) => sum + o.order.totalAmount);
  final inStore = counted
      .where((o) => o.order.channel == OrderChannel.inStore)
      .fold(0.0, (sum, o) => sum + o.order.totalAmount);
  final unpaid = counted
      .where((o) => o.order.paymentStatus != PaymentStatus.paid)
      .fold(0.0, (sum, o) => sum + o.order.totalAmount);

  buffer.writeln(_row(['Summary']));
  buffer.writeln(_row(['Orders counted', '${counted.length}']));
  buffer.writeln(_row(['Cancelled (excluded)',
      '${orders.length - counted.length}']));
  buffer.writeln(_row(['Revenue', revenue.toStringAsFixed(2)]));
  buffer.writeln(_row(['Delivery revenue', delivery.toStringAsFixed(2)]));
  buffer.writeln(_row(['In-store revenue', inStore.toStringAsFixed(2)]));
  buffer.writeln(_row(['Still to collect', unpaid.toStringAsFixed(2)]));
  if (profit != null) {
    buffer.writeln(_row(['Cost of goods', profit.cost.toStringAsFixed(2)]));
    buffer.writeln(_row(['Profit', profit.profit.toStringAsFixed(2)]));
    buffer.writeln(_row(
        ['Margin %', profit.marginPercent.toStringAsFixed(1)]));
    if (profit.isIncomplete) {
      buffer.writeln(_row([
        'NOTE',
        '${profit.uncostedItems} sold item(s) have no cost price recorded, '
            'so profit is overstated',
      ]));
    }
  }
  buffer.writeln();

  buffer.writeln(_row([
    'Order ID',
    'Date',
    'Channel',
    'Customer',
    'Phone',
    'Status',
    'Payment',
    'Subtotal',
    'Delivery fee',
    'Total',
  ]));

  for (final staffOrder in orders) {
    final order = staffOrder.order;
    buffer.writeln(_row([
      order.id.substring(0, 8).toUpperCase(),
      date.format(order.createdAt.toLocal()),
      order.channel == OrderChannel.inStore ? 'In-store' : 'Delivery',
      staffOrder.customerLabel,
      staffOrder.customerPhone ?? '',
      order.status.label,
      order.paymentStatus.name,
      order.subtotalAmount.toStringAsFixed(2),
      order.deliveryFeeAmount.toStringAsFixed(2),
      order.totalAmount.toStringAsFixed(2),
    ]));
  }

  return buffer.toString();
}

/// Escapes per RFC 4180: wrap in quotes when the value contains a comma,
/// quote or newline, and double any embedded quotes. Shop names and
/// addresses contain commas constantly, and getting this wrong silently
/// shifts every later column.
String _row(List<String> values) => values.map(_escape).join(',');

String _escape(String value) {
  final needsQuotes =
      value.contains(',') || value.contains('"') || value.contains('\n');
  final escaped = value.replaceAll('"', '""');
  return needsQuotes ? '"$escaped"' : escaped;
}
