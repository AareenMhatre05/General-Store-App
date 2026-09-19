import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

import 'screens/address_pick_screen.dart';
import 'screens/addresses_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/order_detail_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/wrong_role_screen.dart';

const _preAuthLocations = {'/welcome', '/login', '/signup'};

GoRouter buildRouter(AppAuthState authState) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authState,
    redirect: (context, state) {
      final loc = state.matchedLocation;

      if (authState.status == AppAuthStatus.loading) {
        return loc == '/splash' ? null : '/splash';
      }

      if (authState.status == AppAuthStatus.unauthenticated) {
        return _preAuthLocations.contains(loc) ? null : '/welcome';
      }

      // Authenticated from here on.
      if (authState.profile!.role != UserRole.customer) {
        return loc == '/wrong-role' ? null : '/wrong-role';
      }
      if (loc == '/splash' || _preAuthLocations.contains(loc)) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (context, state) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(path: '/wrong-role', builder: (context, state) => const WrongRoleScreen()),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) => ProductDetailScreen(
          productId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/addresses', builder: (context, state) => const AddressesScreen()),
      GoRoute(
        path: '/address/pick',
        builder: (context, state) =>
            AddressPickScreen(existing: state.extra as Address?),
      ),
      // No /categories route: it is a page of the home shell, reached by
      // swiping or by the nav bar, not a destination of its own.
      GoRoute(
        path: '/category/:id',
        builder: (context, state) => CategoryProductsScreen(
          categoryId: state.pathParameters['id']!,
          categoryName: state.extra as String? ?? 'Category',
        ),
      ),
      GoRoute(path: '/favorites', builder: (context, state) => const FavoritesScreen()),
      GoRoute(path: '/chat', builder: (context, state) => const ChatInboxScreen()),
      GoRoute(
        path: '/chat/:productId',
        builder: (context, state) => ChatThreadScreen(
          productId: state.pathParameters['productId']!,
          productName: state.extra as String? ?? 'Chat',
        ),
      ),
      GoRoute(path: '/orders', builder: (context, state) => const OrdersScreen()),
      GoRoute(
        path: '/orders/:id',
        builder: (context, state) => OrderDetailScreen(
          orderId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
}
