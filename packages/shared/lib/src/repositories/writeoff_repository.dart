import '../supabase/supabase_bootstrap.dart';

/// One expired/damaged batch taken off the shelf.
class StockWriteoff {
  const StockWriteoff({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    this.unitCost,
    required this.reason,
    required this.refunded,
    required this.refundAmount,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String productName;
  final int quantity;
  final double? unitCost;
  final String reason;
  final bool refunded;
  final double refundAmount;
  final String? notes;
  final DateTime createdAt;

  /// What the goods cost the shop.
  double get costOfGoods => (unitCost ?? 0) * quantity;

  /// What was not recovered from the supplier -- the actual loss.
  double get netLoss {
    final loss = costOfGoods - refundAmount;
    return loss < 0 ? 0 : loss;
  }

  factory StockWriteoff.fromJson(Map<String, dynamic> json) {
    final product = json['products'] as Map<String, dynamic>?;
    return StockWriteoff(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      productName: product?['name'] as String? ?? 'Removed product',
      quantity: json['quantity'] as int,
      unitCost: (json['unit_cost'] as num?)?.toDouble(),
      reason: json['reason'] as String? ?? 'expired',
      refunded: json['refunded'] as bool? ?? false,
      refundAmount: (json['refund_amount'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Totals for a period.
class WriteoffTotals {
  const WriteoffTotals({
    required this.units,
    required this.costOfGoods,
    required this.refundedAmount,
    required this.netLoss,
    required this.entries,
  });

  final int units;
  final double costOfGoods;
  final double refundedAmount;
  final double netLoss;
  final int entries;

  /// Share of the written-off value the supplier made good.
  double get recoveredPercent =>
      costOfGoods <= 0 ? 0 : (refundedAmount / costOfGoods) * 100;
}

/// Expired and damaged stock, and whether the supplier credited it.
///
/// The distinction is the whole point: goods the supplier takes back are
/// a wash, goods they refuse are money the shop simply lost. Recording
/// both the same way would quietly overstate profit.
class WriteoffRepository {
  Future<List<StockWriteoff>> getRecent({int limit = 100}) async {
    final rows = await supabase
        .from('stock_writeoffs')
        .select('*, products(name)')
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(StockWriteoff.fromJson).toList();
  }

  /// [unitCost] is normally left null: a trigger fills it in from the
  /// product's recorded cost, and snapshots it so a later price change
  /// cannot rewrite what this loss was worth.
  Future<void> record({
    required String productId,
    required int quantity,
    required bool refunded,
    double refundAmount = 0,
    String reason = 'expired',
    String? notes,
    double? unitCost,
  }) async {
    await supabase.from('stock_writeoffs').insert({
      'product_id': productId,
      'quantity': quantity,
      'refunded': refunded,
      'refund_amount': refunded ? refundAmount : 0,
      'reason': reason,
      'notes': notes,
      if (unitCost != null) 'unit_cost': unitCost,
      'recorded_by': supabase.auth.currentUser?.id,
    });
  }

  Future<void> delete(String id) async {
    await supabase.from('stock_writeoffs').delete().eq('id', id);
  }

  Future<WriteoffTotals> totalsBetween({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await supabase.rpc('writeoff_totals_between', params: {
      'p_from': from.toIso8601String(),
      'p_to': to.toIso8601String(),
    });
    final row = (rows as List).isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(rows.first as Map);
    return WriteoffTotals(
      units: (row['units'] as num?)?.toInt() ?? 0,
      costOfGoods: (row['cost_of_goods'] as num?)?.toDouble() ?? 0,
      refundedAmount: (row['refunded_amount'] as num?)?.toDouble() ?? 0,
      netLoss: (row['net_loss'] as num?)?.toDouble() ?? 0,
      entries: (row['entries'] as num?)?.toInt() ?? 0,
    );
  }
}
