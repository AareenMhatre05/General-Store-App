import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'cart/cart_controller.dart';
import 'router.dart';
import 'widgets/order_status_announcer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeSupabase();
  // Loaded before runApp so the app never paints the wrong theme for a
  // frame and then snaps to the right one.
  final themeController = await ThemeController.load();
  runApp(CustomerApp(themeController: themeController));
}

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => AuthRepository()),
        ChangeNotifierProvider(
          create: (context) => AppAuthState(context.read<AuthRepository>()),
        ),
        Provider(create: (_) => CatalogRepository()),
        Provider(create: (_) => AddressRepository()),
        Provider(create: (_) => RouteRepository()),
        Provider(create: (_) => DeliveryRepository()),
        Provider(create: (_) => OrderRepository()),
        Provider(create: (_) => ChatRepository()),
        Provider(create: (_) => FavoritesRepository()),
        // Proxied off the auth state so the cart follows the signed-in
        // user: their saved cart is fetched back on login, and cleared
        // from memory on logout rather than handed to whoever logs in
        // next on the same phone.
        ChangeNotifierProxyProvider<AppAuthState, CartController>(
          create: (context) => CartController(context.read<CatalogRepository>()),
          update: (context, auth, cart) =>
              cart!..syncWithUser(auth.profile?.id),
        ),
        ChangeNotifierProvider.value(value: themeController),
        Provider<GoRouter>(
          create: (context) => buildRouter(context.read<AppAuthState>()),
        ),
      ],
      child: Builder(
        builder: (context) {
          return MaterialApp.router(
            title: 'Kavita General Stores',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: context.watch<ThemeController>().mode,
            routerConfig: context.read<GoRouter>(),
            // Wrapped around the whole app so the shop's decision reaches
            // the customer wherever they are, not only on the order screen.
            builder: (context, child) =>
                OrderStatusAnnouncer(child: child ?? const SizedBox.shrink()),
          );
        },
      ),
    );
  }
}
