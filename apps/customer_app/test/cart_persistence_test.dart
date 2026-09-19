import 'package:customer/cart/cart_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the real catalog so the test never touches the network.
/// Restoring deliberately re-reads the product, so this also lets the
/// test change a price between "sessions".
class _FakeCatalog extends CatalogRepository {
  _FakeCatalog(this.products);

  final Map<String, Product> products;
  int fetchCount = 0;

  @override
  Future<Product> getProduct(String id) async {
    fetchCount++;
    final product = products[id];
    if (product == null) throw Exception('no such product');
    return product;
  }
}

Product _product({
  required String id,
  String name = 'Amul Butter',
  double price = 60,
  bool isActive = true,
}) {
  final now = DateTime(2026, 8, 20);
  return Product(
    id: id,
    name: name,
    unit: '100 g',
    price: price,
    stockQuantity: 20,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  const userId = 'user-1';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a cart survives closing and reopening the app', () async {
    final butter = _product(id: 'p1');
    final rice = _product(id: 'p2', name: 'Rice', price: 250);

    final first = CartController(_FakeCatalog({'p1': butter, 'p2': rice}));
    first.syncWithUser(userId);
    await Future<void>.delayed(Duration.zero);
    first.add(butter, quantity: 3);
    first.add(rice);
    await Future<void>.delayed(Duration.zero);

    // A fresh controller is exactly what the next launch builds.
    final second = CartController(_FakeCatalog({'p1': butter, 'p2': rice}));
    second.syncWithUser(userId);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(second.itemCount, 4);
    expect(second.lines.firstWhere((l) => l.product.id == 'p1').quantity, 3);
    expect(second.subtotal, 60 * 3 + 250);
  });

  test('restored lines carry today\'s price, not the saved one', () async {
    final catalog = _FakeCatalog({'p1': _product(id: 'p1')});
    final first = CartController(catalog);
    first.syncWithUser(userId);
    await Future<void>.delayed(Duration.zero);
    first.add(_product(id: 'p1'), quantity: 2);
    await Future<void>.delayed(Duration.zero);

    // The shop puts butter up overnight.
    catalog.products['p1'] = _product(id: 'p1', price: 75);

    final second = CartController(catalog);
    second.syncWithUser(userId);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(second.subtotal, 150);
  });

  test('a product withdrawn from sale drops out instead of breaking the cart',
      () async {
    final rice = _product(id: 'p2', name: 'Rice', price: 250);
    final catalog = _FakeCatalog({
      'p1': _product(id: 'p1'),
      'p2': rice,
    });
    final first = CartController(catalog);
    first.syncWithUser(userId);
    await Future<void>.delayed(Duration.zero);
    first.add(_product(id: 'p1'));
    first.add(rice);
    await Future<void>.delayed(Duration.zero);

    catalog.products.remove('p1');
    catalog.products['p2'] = rice;

    final second = CartController(catalog);
    second.syncWithUser(userId);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(second.lines.length, 1);
    expect(second.lines.single.product.id, 'p2');
  });

  test('one person\'s cart is not handed to the next person on the phone',
      () async {
    final butter = _product(id: 'p1');
    final catalog = _FakeCatalog({'p1': butter});

    final controller = CartController(catalog);
    controller.syncWithUser(userId);
    await Future<void>.delayed(Duration.zero);
    controller.add(butter, quantity: 5);
    await Future<void>.delayed(Duration.zero);

    controller.syncWithUser('user-2');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.isEmpty, isTrue);

    // ...and the first person still has theirs when they come back.
    controller.syncWithUser(userId);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.itemCount, 5);
  });

  test('checking out empties the saved cart too', () async {
    final butter = _product(id: 'p1');
    final catalog = _FakeCatalog({'p1': butter});

    final first = CartController(catalog);
    first.syncWithUser(userId);
    await Future<void>.delayed(Duration.zero);
    first.add(butter);
    await Future<void>.delayed(Duration.zero);
    first.clear();
    await Future<void>.delayed(Duration.zero);

    final second = CartController(catalog);
    second.syncWithUser(userId);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(second.isEmpty, isTrue);
  });
}
