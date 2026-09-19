import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

import 'screens/categories_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/edit_sale_screen.dart';
import 'screens/in_store_sale_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/login_screen.dart';
import 'screens/my_deliveries_screen.dart';
import 'screens/offers_screen.dart';
import 'screens/order_detail_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/price_tags_screen.dart';
import 'screens/product_form_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/store_settings_screen.dart';
import 'screens/team_screen.dart';
import 'screens/writeoffs_screen.dart';
import 'screens/wrong_role_screen.dart';

const _preAuthLocations = {'/login', '/signup'};
// Delivery partners use this app too. What they can actually read is
// decided by RLS, not here: is_staff_or_owner() includes them, while
// product_costs and order_item_costs are behind can_see_costs(), which
// does not -- so supplier prices and margins stay with staff and owner.
const _allowedRoles = {UserRole.staff, UserRole.owner, UserRole.delivery};

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
        return _preAuthLocations.contains(loc) ? null : '/login';
      }

      // Authenticated from here on.
      final role = authState.profile!.role;
      if (!_allowedRoles.contains(role)) {
        return loc == '/wrong-role' ? null : '/wrong-role';
      }

      // A delivery partner's app is one screen. The database would
      // return almost nothing on the others anyway -- they can only read
      // orders assigned to them -- so sending them to a dashboard of
      // empty totals would just look broken.
      if (role == UserRole.delivery) {
        return loc == '/deliveries' ? null : '/deliveries';
      }

      if (loc == '/splash' || _preAuthLocations.contains(loc)) {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(path: '/wrong-role', builder: (context, state) => const WrongRoleScreen()),
      GoRoute(
        path: '/deliveries',
        builder: (context, state) => const MyDeliveriesScreen(),
      ),
      GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
      GoRoute(path: '/inventory', builder: (context, state) => const InventoryScreen()),
      GoRoute(path: '/categories', builder: (context, state) => const CategoriesScreen()),
      GoRoute(path: '/orders', builder: (context, state) => const OrdersScreen()),
      GoRoute(
        path: '/orders/:id',
        builder: (context, state) =>
            StaffOrderDetailScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/product/new',
        builder: (context, state) => const ProductFormScreen(productId: null),
      ),
      GoRoute(
        path: '/product/:id/edit',
        builder: (context, state) =>
            ProductFormScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/offers', builder: (context, state) => const OffersScreen()),
      GoRoute(
        path: '/store-settings',
        builder: (context, state) => const StoreSettingsScreen(),
      ),
      GoRoute(path: '/sales', builder: (context, state) => const SalesScreen()),
      GoRoute(path: '/team', builder: (context, state) => const TeamScreen()),
      GoRoute(path: '/writeoffs', builder: (context, state) => const WriteoffsScreen()),
      GoRoute(
        path: '/orders/:id/edit',
        builder: (context, state) =>
            EditSaleScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/chat', builder: (context, state) => const StaffChatInboxScreen()),
      GoRoute(
        path: '/chat/:customerId/:productId',
        builder: (context, state) => StaffChatThreadScreen(
          customerId: state.pathParameters['customerId']!,
          productId: state.pathParameters['productId']!,
          productName: state.extra as String? ?? 'Chat',
        ),
      ),
      GoRoute(path: '/price-tags', builder: (context, state) => const PriceTagsScreen()),
      GoRoute(
        path: '/in-store-sale',
        builder: (context, state) => const InStoreSaleScreen(),
      ),
    ],
  );
}
