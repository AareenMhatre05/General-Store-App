import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartLine {
  CartLine({required this.product, required this.quantity});

  final Product product;
  int quantity;

  /// Uses the offer-adjusted price, matching what the server will
  /// charge -- the cart is an estimate of a total the DB recomputes.
  double get subtotal => product.sellingPrice * quantity;
}

/// The shopping cart, kept on the device between launches.
///
/// There is still no `cart` table. What is stored is only a list of
/// product ids and quantities; the products themselves are re-fetched on
/// startup, so a cart left overnight shows this morning's prices, this
/// morning's offers, and silently drops anything that has since been
/// taken off sale. Storing the whole product would be less work and
/// would quietly show people a price the store no longer honours.
///
/// The saved list is keyed by user id, so two people sharing a phone do
/// not inherit each other's shopping.
class CartController extends ChangeNotifier {
  CartController(this._catalog);

  final CatalogRepository _catalog;
  final Map<String, CartLine> _lines = {};

  String? _userId;
  bool _isRestoring = false;

  /// True while the saved cart is being fetched back, so the cart screen
  /// can wait instead of flashing "your cart is empty" first.
  bool get isRestoring => _isRestoring;

  List<CartLine> get lines => List.unmodifiable(_lines.values);

  int get itemCount => _lines.values.fold(0, (sum, line) => sum + line.quantity);

  double get subtotal => _lines.values.fold(0.0, (sum, line) => sum + line.subtotal);

  bool get isEmpty => _lines.isEmpty;

  void add(Product product, {int quantity = 1}) {
    final existing = _lines[product.id];
    if (existing != null) {
      existing.quantity += quantity;
    } else {
      _lines[product.id] = CartLine(product: product, quantity: quantity);
    }
    _persist();
    notifyListeners();
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      _lines.remove(productId);
    } else {
      _lines[productId]?.quantity = quantity;
    }
    _persist();
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    _persist();
    notifyListeners();
  }

  /// Called whenever the signed-in user changes, including at startup.
  /// Cheap to call repeatedly -- it does nothing unless the user really
  /// changed.
  void syncWithUser(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    _lines.clear();
    // Called from a provider's `update`, which runs during build --
    // notifying listeners synchronously there would rebuild widgets
    // mid-build. The microtask lands immediately after.
    scheduleMicrotask(() {
      notifyListeners();
      if (userId != null) unawaited(_restore(userId));
    });
  }

  String _keyFor(String userId) => 'cart_v1_$userId';

  Future<void> _persist() async {
    final userId = _userId;
    if (userId == null) return;
    final payload = <String, int>{
      for (final line in _lines.values) line.product.id: line.quantity,
    };
    final prefs = await SharedPreferences.getInstance();
    if (payload.isEmpty) {
      await prefs.remove(_keyFor(userId));
    } else {
      await prefs.setString(_keyFor(userId), jsonEncode(payload));
    }
  }

  Future<void> _restore(String userId) async {
    _isRestoring = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyFor(userId));
      if (raw == null) return;

      final saved = (jsonDecode(raw) as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, (value as num).toInt()));
      if (saved.isEmpty) return;

      // One product at a time, tolerating failures: a product that has
      // been deleted or deactivated should drop out of the cart, not
      // stop the whole restore.
      final restored = <String, CartLine>{};
      for (final entry in saved.entries) {
        try {
          final product = await _catalog.getProduct(entry.key);
          if (!product.isActive) continue;
          final quantity = entry.value.clamp(1, 99);
          restored[product.id] =
              CartLine(product: product, quantity: quantity);
        } catch (_) {
          continue;
        }
      }

      // Another sign-in may have landed while we were fetching.
      if (_userId != userId) return;
      _lines
        ..clear()
        ..addAll(restored);
      await _persist();
    } catch (_) {
      // A cart that cannot be read is not worth crashing over.
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }
}
