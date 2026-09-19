import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'router.dart';
import 'widgets/new_message_watcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeSupabase();
  // Loaded before runApp so the app never paints the wrong theme for a
  // frame and then snaps to the right one.
  final themeController = await ThemeController.load();
  runApp(StaffApp(themeController: themeController));
}

class StaffApp extends StatelessWidget {
  const StaffApp({super.key, required this.themeController});

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
        Provider(create: (_) => CategoryRepository()),
        Provider(create: (_) => OrderRepository()),
        Provider(create: (_) => ProductRepository()),
        Provider(create: (_) => OfferRepository()),
        Provider(create: (_) => StoreRepository()),
        Provider(create: (_) => ChatRepository()),
        Provider(create: (_) => WriteoffRepository()),
        Provider(create: (_) => StaffInviteRepository()),
        Provider(create: (_) => DeliveryRepository()),
        Provider(create: (_) => RouteRepository()),
        Provider(create: (_) => LocationService()),
        ChangeNotifierProvider.value(value: themeController),
        Provider<GoRouter>(
          create: (context) => buildRouter(context.read<AppAuthState>()),
        ),
      ],
      child: Builder(
        builder: (context) {
          return MaterialApp.router(
            title: 'K.G.S Staff',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: context.watch<ThemeController>().mode,
            routerConfig: context.read<GoRouter>(),
            builder: (context, child) =>
                NewMessageWatcher(child: child ?? const SizedBox.shrink()),
          );
        },
      ),
    );
  }
}
