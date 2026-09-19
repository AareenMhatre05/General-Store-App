# Flow

Traces of how execution actually moves — file by file, function by function,
including the database triggers that fire after a write. If you are about to
change something and want to know what else runs, find it here.

Companion docs: [Architecture.md](Architecture.md) (what exists),
[Decisions.md](Decisions.md) (why).

Notation: `→` = calls / navigates to, `⇒` = database trigger fires.

---

## 1. App boot

Identical in both apps.

```
main()                                        apps/*/lib/main.dart
 → WidgetsFlutterBinding.ensureInitialized()
 → initializeSupabase()                       shared: src/supabase/supabase_bootstrap.dart
     → Supabase.initialize(url, publishableKey)   restores any persisted session from disk
 → runApp(CustomerApp | StaffApp)
     → MultiProvider builds, in order:
         AuthRepository
         AppAuthState(authRepository)         ← constructor immediately calls _refresh()
         ...other repositories
         CartController                       (customer only)
         GoRouter = buildRouter(authState)    ← built ONCE, never rebuilt
     → MaterialApp.router(routerConfig: …, theme: AppTheme.dark)
```

`AppAuthState`'s constructor starts `_refresh()` and subscribes to
`authStateChanges`. Until that first refresh completes, `status` is
`loading`, so the router parks on `/splash`.

---

## 2. The auth gate (runs on *every* navigation)

```
GoRouter.redirect(context, state)             apps/*/lib/router.dart
 │
 ├─ status == loading          → '/splash'  (or stay if already there)
 ├─ status == unauthenticated  → '/welcome' (customer) | '/login' (staff)
 │                                unless already on a pre-auth route
 ├─ role not allowed here      → '/wrong-role'
 └─ on a pre-auth route        → '/home' (customer) | '/dashboard' (staff)
```

What makes it re-run: `refreshListenable: authState`. Any
`notifyListeners()` from `AppAuthState` — i.e. any sign-in, sign-out, token
refresh, or profile reload — makes go_router re-evaluate the redirect for the
current location. This is the whole role-gating mechanism; there is no
per-screen auth check anywhere.

`/wrong-role` (`wrong_role_screen.dart`) calls
`AppAuthState.signOut()` in its `initState`, which cascades:
`supabase.auth.signOut()` ⇒ `authStateChanges` fires ⇒ `_refresh()` ⇒
`notifyListeners()` ⇒ redirect → `/welcome` or `/login`.

---

## 3. Customer signup

```
SignupScreen._submit()                        customer_app/lib/screens/signup_screen.dart
 → _formKey.currentState!.validate()          name optional, phone ≥10 digits, email, password ≥6
 → AuthRepository.signUpCustomer(email, password, fullName, phone)
     → supabase.auth.signUp(data: {full_name, phone})     ← NO invite_code
        ⇒ INSERT auth.users
        ⇒ trigger on_auth_user_created → handle_new_user()      SECURITY DEFINER
             INSERT profiles (id, full_name, phone)              role defaults to 'customer'
             raw_user_meta_data->>'invite_code' is null → skip the invite branch
 → response.session == null ?                 ← null means email confirmation is ON
     yes → nothing to undo; the user is not signed in
     no  → AuthRepository.signOut()           ← undo the automatic sign-in
 → SnackBar ("Account created…") + router.go('/login')
```

**Why the explicit sign-out:** with Supabase's email confirmation switched
off, `signUp` returns a live session, so the user is already authenticated
the moment the account is created — and the router's redirect would carry
them past `/login` straight into `/home`. Signing out is what makes
"account creation ends at the login screen" actually hold in both auth
configurations. See Decisions.md D34.

`router` and `messenger` are captured from `context` *before* the awaits
(D22), so nothing touches a possibly-disposed context afterwards.

## 4. Staff/owner signup

Same shape, one branch different:

```
staff_app SignupScreen._submit()
 → AuthRepository.signUpStaff(email, password, inviteCode, fullName)
     → supabase.auth.signUp(data: {invite_code, full_name})
        ⇒ handle_new_user()
             INSERT profiles (…)                              role = 'customer' initially
             v_code is not null →
               SELECT staff_invites WHERE lower(email)=lower(new.email)
                                      AND invite_code = v_code
                                      AND used_at IS NULL
                                      AND expires_at > now()
               ├─ no match → RAISE EXCEPTION  ⇒ the whole signup is rolled back
               └─ match    → UPDATE profiles SET role = invite.role
                             UPDATE staff_invites SET used_at, used_by
```

Note the ordering: the profile is created first and *then* promoted, inside
one transaction. A failed invite aborts the `auth.users` insert too — no
orphan account is left behind.

On success the staff screen does the same sign-out-then-`/login` dance as the
customer one.

## 5. Login (both apps)

```
LoginScreen._submit()
 → AuthRepository.signIn(email, password)
     → supabase.auth.signInWithPassword(...)
        ⇒ authStateChanges → AppAuthState._refresh()
             → AuthRepository.currentProfile()   SELECT profiles WHERE id = auth.uid()
             → status = authenticated, profile = row
             → notifyListeners()
        ⇒ router redirect → '/home' | '/dashboard' | '/wrong-role'
```

A staff member signing into the customer app authenticates *successfully*,
then lands on `/wrong-role`, which signs them straight back out. The rejection
is client-side UX; the real protection is that RLS gives them nothing useful
either way.

---

## 6. Browsing (customer home)

```
HomeScreen.initState → _loadFuture = _load()
 _load():
   CatalogRepository.getCategories()        SELECT categories WHERE is_active ORDER BY sort_order
   CatalogRepository.getProducts()          SELECT products WHERE is_active ORDER BY name
   CatalogRepository.getActiveOffers()      SELECT offers WHERE is_active
   CatalogRepository.getPrimaryImageUrls(ids)
       SELECT product_images WHERE product_id IN (…) ORDER BY is_primary DESC, sort_order
       → storage.from('product-images').getPublicUrl(path)   for the first row per product
   setState(...)
```

Search and category filtering are **client-side** over the already-loaded
list (`_filteredProducts`) — no refetch per keystroke.

Taps: product card → `context.go('/product/:id')`; cart icon → `/cart`;
bottom nav index 3 → `/profile`.

## 7. Product detail + inquiry chat

```
ProductDetailScreen._load()
 → CatalogRepository.getProduct(id) + getProductImages(id)

"Chat for Personalized Order" →  showModalBottomSheet
 → StreamBuilder(stream: ChatRepository.streamMessages(customerId, productId))
       supabase.from('product_inquiries').stream(primaryKey: ['id'])
       filtered to this customer+product, oldest first
       (Realtime — product_inquiries is in the supabase_realtime publication)
 → send → ChatRepository.sendMessage(...)
       INSERT product_inquiries (customer_id, product_id, sender_role, message)
       RLS: customer may insert only their own rows
       → the open stream emits the new message; no manual refresh
```

## 8. Add to cart

```
ProductCard.onAdd / detail "Add to Cart"
 → CartController.add(product)          customer_app/lib/cart/cart_controller.dart
     mutates the in-memory Map<String, CartLine>
     notifyListeners() → header badge + cart screen rebuild
```

Nothing is persisted. Closing the app empties the cart, by design.

---

## 9. Checkout — the longest chain in the system

```
CartScreen
 ├─ initState → AddressRepository.getMyAddresses()   (defaults sorted first)
 │              → auto-select the first, which prices it
 │
 ├─ tap an address → _select(address)
 │    → CatalogRepository.getDeliveryFeeForCoords(address.lat, address.lng)
 │        RPC get_delivery_fee_for_coords
 │          → ST_MakePoint → get_delivery_fee_for_point(store, point)
 │          → ST_Distance vs store_settings.location → matching delivery_fee_tiers row
 │        (store location unset ⇒ null distance ⇒ ₹0 — see RELEASE.md §4)
 │
 ├─ "New address" → push /address/pick  (map picker, below) → select what it returns
 │
 ├─ "Use current" → LocationService.current()
 │        service enabled? → permission (asked HERE, at point of use)
 │        → getCurrentPosition(high, 20s) or last-known fallback
 │    → upsertAddress(label:'Current Location', …) → select
 │
 ├─ "Schedule" → showDatePicker → showTimePicker → _scheduledFor
 │
 └─ "Place Order" → _placeOrder()
      guard: _deliveryAddressId != null
      → OrderRepository.placeDeliveryOrder(deliveryAddressId, items, scheduledFor)
```

Inside `placeDeliveryOrder`, three statements and the triggers each one fires:

```
1. INSERT INTO orders (customer_id = auth user id,   ← required; no column default,
                                                       and RLS demands it match
                       channel='delivery',
                       status = scheduledFor != null ? 'scheduled' : 'pending_payment',
                       delivery_address_id, scheduled_for, notes)
   ⇒ BEFORE INSERT  compute_delivery_fee_for_order()
        ST_Distance(store_settings.location, addresses.location)
        → NEW.distance_meters, NEW.delivery_fee_amount = get_delivery_fee(distance)
   ⇒ RLS: "Customers can place their own delivery orders"

2. INSERT INTO order_items (…)   one row per cart line
   ⇒ BEFORE INSERT  set_order_item_price()
        customer → NEW.unit_price := effective_unit_price(product_id)
                   (whatever the client sent is discarded)
        staff    → a sent price is honoured, for negotiated counter sales
        effective_unit_price → best_offer_for_product → product/category/
                   store-wide precedence, biggest discount breaks ties
   ⇒ AFTER INSERT  record_sale_inventory_adjustment()
        INSERT inventory_adjustments (change_quantity = -quantity, reason='sale',
                                      reference_order_id)
        ⇒ AFTER INSERT  apply_inventory_adjustment()
             UPDATE products SET stock_quantity = stock_quantity + change_quantity
   ⇒ AFTER INSERT  order_items_recalculate_totals()
        → recalculate_order_totals(order_id)          SECURITY DEFINER
             orders.subtotal_amount = SUM(order_items.subtotal)
             orders.total_amount    = subtotal_amount + delivery_fee_amount

3. SELECT the order back → Order.fromJson   (now carrying server-computed totals)
```

Then:

```
      → CartController.clear()
      → SnackBar + context.go('/orders/{order.id}')
```

Client-side totals shown before checkout are display-only. **The order's real
money values are whatever the triggers computed** — the client never sends a
fee or a total, and has no UPDATE policy on `orders` to change one.

## 10. Scheduled orders

```
pg_cron 'promote-scheduled-orders'  — every minute
  UPDATE orders SET status='confirmed'
   WHERE status='scheduled' AND scheduled_for <= now()
```

No app code is involved. The order simply appears in staff's normal queue at
the right time.

## 11. Order history

```
Profile "My Orders" → context.go('/orders')

OrdersScreen._load()
 → OrderRepository.getMyOrders()        SELECT orders ORDER BY created_at DESC
                                        RLS returns only this customer's rows
 → OrderRepository.getItemCounts(ids)   one query for all rows, summed client-side
 tap → context.go('/orders/{id}')

OrderDetailScreen._load()
 → OrderRepository.getOrder(id)
 → OrderRepository.getOrderItemsDetailed(id)
      SELECT order_items.*, products(name, unit)   ← PostgREST embed
      missing product → "Removed item" placeholder, line is still shown
 renders _StatusTimeline over OrderStatus.progressSteps
```

The same `getMyOrders()` call, made by staff, returns **every** order —
identical query, different RLS outcome. `getAllOrders()` is an alias that
reads better on the staff side.

## 11b. Adding an address (the map picker)

```
AddressPickScreen                       customer_app/lib/screens/address_pick_screen.dart
 ├─ initState → no saved pin? LocationService.current() → move map there
 │              editing?      open on the saved pin
 │
 ├─ map dragged → onPositionChanged(hasGesture) → _pin = centre
 │                → debounce 600ms → Geocoding().placemarkFromCoordinates(_pin)
 │                → "name, subLocality, locality" shown under the pin
 │                → locality/postalCode remembered to prefill city/pincode
 │                (geocoder returns nothing → fall back to showing lat/lng;
 │                 the pin is still exact, which is what pricing needs)
 │
 └─ "Confirm Location" → _AddressDetailsSheet
        house/flat (required), landmark, city, pincode, Home|Work|Other, default?
        → AddressRepository.upsertAddress(...)
             RPC upsert_address → returns addresses_with_coords shape
        → pops the saved Address back to whoever pushed the route
```

## 12. Profile edit

```
ProfileScreen._editProfile(profile)
 → showModalBottomSheet (name + phone fields) → pops true
 → capture locals BEFORE awaiting:            ← required; see Decisions.md #14
     authRepository = context.read<AuthRepository>()
     authState      = context.read<AppAuthState>()
 → authRepository.updateProfile(fullName, phone)
     UPDATE profiles SET full_name, phone WHERE id = auth.uid()
     ⇒ prevent_role_self_escalation() sees role unchanged → allows
     ⇒ profiles_set_updated_at
 → authState.refreshProfile()  → _refresh() → notifyListeners() → UI updates
```

---

## 12b. Payment (cash on delivery)

There is no payment flow in the customer app. An unpaid order shows a
"pay in cash when your order arrives" note, and money changes hands in
person. `payment_status` is moved to `paid` by staff — automatically when
they mark the order delivered, or manually via "Mark as Paid (cash)".

Customers have no UPDATE policy on `orders`, so they cannot declare their
own order paid.

## 12c. Staff fulfilling an order

```
OrdersScreen (filter defaults to "Needs action" = status.isOpen)
 → OrderRepository.getOrdersForStaff(...)   orders + profiles + addresses embedded
 → tap → StaffOrderDetailScreen

_advance(next)
 → updateOrderStatus(orderId, status.nextStatus)
      pending_payment/scheduled → confirmed → preparing
      → out_for_delivery → delivered
 → if delivered && payment still pending:
      updatePaymentStatus(paid)      ← handing goods over settles a cash order

_cancel()
 → updateOrderStatus(cancelled)
   ⇒ AFTER UPDATE  restock_on_order_cancellation()
        INSERT inventory_adjustments (+quantity, reason='cancellation')
        ⇒ apply_inventory_adjustment() → products.stock_quantity restored
```

In-store sales skip all of it: `createInStoreSale()` writes them as
`delivered`, then the screen marks them paid.

## 13. Staff: adjust stock

```
InventoryScreen stepper (+/-)
 → ProductRepository.adjustStock(productId, changeQuantity, reason)
     INSERT inventory_adjustments (…)
     ⇒ apply_inventory_adjustment() → UPDATE products.stock_quantity
 → reload products
```

`products.stock_quantity` is **never** written directly by any client. Every
change goes through the ledger, so stock always has an audit trail.

## 14. Staff: create/edit a product

```
ProductFormScreen._save()
 → new:  ProductRepository.createProduct(name, price, mrp, unit, categoryId, …)
         then, if an opening stock was entered:
           ProductRepository.adjustStock(...)   ⇒ ledger ⇒ stock_quantity
 → edit: ProductRepository.updateProduct(...)
 → if an image was picked:
     ProductRepository.uploadProductImage(productId, bytes, filename)
       storage.from('product-images').uploadBinary(path, bytes)
       INSERT product_images (product_id, storage_path, is_primary = first image?)
 → context.go('/inventory')
```

## 15. Staff: offers

```
OffersScreen._load()   → OfferRepository.getAllOffers()   (incl. inactive)
                       + CatalogRepository.getCategories() / getProducts() for scope pickers
create → OfferRepository.createOffer(title, discountType, discountValue, scope, …)
toggle → OfferRepository.setActive(offerId, isActive)
```

Customers see offers through `CatalogRepository.getActiveOffers()`, which is
a different query against the same table — RLS restricts customers to active,
in-window offers.

## 16. Staff: dashboard

```
DashboardScreen._load()
 → OrderRepository.getAllOrders()        RLS gives staff everything
 → CatalogRepository.getProducts()
 computed client-side:
   today's sales   = sum of totals for orders created today
   pending count   = status in (confirmed, preparing, out_for_delivery)
   low stock count = products under the threshold
   recent sales    = first N orders
```

Aggregates are computed in Dart over the fetched lists. Fine at family-store
volume; if order count grows, these become SQL views or RPCs.

---

## 17. Where a change ripples

| If you change… | Also check |
|---|---|
| a table column | its model's `fromJson`, every repository selecting it, RLS policies naming it |
| an RLS policy | both apps — the same repository method is often called by both |
| `handle_new_user()` | customer signup **and** staff invite redemption both run through it |
| an order/order_item trigger | totals, stock ledger, and the cancellation restock path |
| `AppAuthState` | both routers' redirects — this is the single auth source |
| a token in `design.md` | `packages/shared/lib/src/theme/` must be updated to match |
