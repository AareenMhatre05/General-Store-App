# Architecture

The system map for Kavita General Stores (K.G.S). Read this before touching
anything — it says what exists, where it lives, and what depends on it.

Companion docs: [Decisions.md](Decisions.md) (*why* each choice was made),
[Flow.md](Flow.md) (*how* execution moves through it), [design.md](design.md)
(visual tokens — the single source of truth for UI styling).

---

## 1. Shape of the system

```
┌──────────────────┐        ┌──────────────────┐
│  customer_app    │        │   staff_app      │
│  (Play Store)    │        │  (sideloaded)    │
│  role: customer  │        │  role: staff/    │
│                  │        │        owner     │
└────────┬─────────┘        └────────┬─────────┘
         │                           │
         └──────────┬────────────────┘
                    │  both depend on
           ┌────────▼─────────┐
           │ packages/shared  │  models · repositories · auth state
           │                  │  theme · supabase client
           └────────┬─────────┘
                    │  supabase-flutter (anon key + user JWT)
           ┌────────▼──────────────────────────────────┐
           │ Supabase project yswvraurldyxatjcuvxg     │
           │  Auth · Postgres+PostGIS · Storage        │
           │  Realtime · pg_cron                       │
           │  RLS is the ONLY authorization boundary   │
           └───────────────────────────────────────────┘
```

**One backend, two clients, one shared package.** There is no server of our
own — no API layer, no backend-for-frontend. The apps talk to Supabase
directly, and every authorization rule lives in Postgres RLS policies. This
is load-bearing: a client is assumed to be hostile and rewritable, so nothing
security-relevant may be enforced in Dart.

---

## 2. Repo layout

```
d:\General Store App\
├─ apps/
│  ├─ customer_app/          Flutter app — browse, order, track
│  │  ├─ lib/
│  │  │  ├─ main.dart              provider wiring + MaterialApp.router
│  │  │  ├─ router.dart            go_router routes + customer role gate
│  │  │  ├─ cart/cart_controller.dart
│  │  │  ├─ screens/               one file per screen
│  │  │  └─ widgets/               product_card, order_status_chip
│  │  └─ android/app/src/main/AndroidManifest.xml   (location permissions)
│  └─ staff_app/             Flutter app — inventory, pricing, offers, sales
│     └─ lib/  (same layout; widgets/staff_scaffold.dart is the shell)
├─ packages/
│  └─ shared/                local path dependency used by both apps
│     └─ lib/
│        ├─ shared.dart            barrel — the ONLY public entry point
│        └─ src/
│           ├─ supabase/           config + initializeSupabase()
│           ├─ models/             plain immutable data classes
│           ├─ repositories/       all Supabase I/O
│           ├─ auth/               AppAuthState (session + role)
│           ├─ theme/              design.md tokens as Dart
│           └─ utils/currency.dart formatInr()
├─ supabase/migrations/      19 SQL files — the schema's source of truth
├─ design.md                 Lumina Marketplace design system
├─ Architecture.md           this file
├─ Decisions.md              decision log
├─ Flow.md                   execution traces
└─ .mcp.json                 Supabase MCP server (project-scoped, NO secrets)
```

**Import rule:** apps import `package:shared/shared.dart` only. Nothing
reaches into `packages/shared/lib/src/...` directly — if a symbol is needed,
it gets exported from the barrel.

---

## 3. Database

19 migrations, applied in filename-timestamp order via `supabase db push`.
Migrations are the source of truth; the dashboard is never used to change
schema (see Decisions.md #4).

### 3.1 Tables

| Table | Purpose | Key columns |
|---|---|---|
| `profiles` | one row per auth user; **holds the role** | `id`→`auth.users`, `role`, `full_name`, `phone` |
| `staff_invites` | owner-issued invites that let a signup land as staff/owner | `email`, `role`, `invite_code`, `expires_at`, `used_at`, `used_by` |
| `store_settings` | singleton (id=1): the store's location | `location` (geography) |
| `delivery_fee_tiers` | distance bands → fee | `min_distance_meters`, `max_distance_meters`, `fee_amount` |
| `addresses` | saved customer delivery addresses | `customer_id`, `location` (geography), `is_default` |
| `categories` | product categories | `name`, `sort_order`, `is_active` |
| `products` | catalog | `price`, `mrp`, `unit`, `stock_quantity`, `barcode`, `is_active`, `is_featured` |
| `product_images` | image records pointing into Storage | `product_id`, `storage_path`, `is_primary`, `sort_order` |
| `inventory_adjustments` | **append-only** stock ledger | `product_id`, `change_quantity`, `reason`, `reference_order_id` |
| `orders` | one row per order/sale | `channel`, `status`, `payment_status`, `delivery_address_id`, `distance_meters`, `subtotal_amount`, `delivery_fee_amount`, `total_amount`, `scheduled_for` |
| `order_items` | order lines | `order_id`, `product_id`, `quantity`, `unit_price`, `subtotal` |
| `offers` | discounts | `discount_type`, `discount_value`, `scope`, `starts_at`, `ends_at`, `is_active` |
| `product_inquiries` | pre-purchase product Q&A chat | `customer_id`, `product_id`, `sender_role`, `message` |

### 3.2 Enums

`user_role` (customer/staff/owner) · `order_channel` (delivery/in_store) ·
`order_status` (pending_payment/scheduled/confirmed/preparing/
out_for_delivery/delivered/cancelled) · `payment_status`
(pending/paid/failed/refunded) · `discount_type` (percentage/flat) ·
`offer_scope` (all_products/category/product) ·
`inventory_adjustment_reason`.

### 3.3 Functions

**Role helpers** (used by nearly every RLS policy):
- `current_role_name()` — the caller's role from `profiles`
- `is_staff_or_owner()`, `is_owner()`

**Auth lifecycle:**
- `handle_new_user()` — `SECURITY DEFINER`, fires on `auth.users` insert.
  Creates the `profiles` row from signup metadata (`full_name`, `phone`),
  then, if `invite_code` metadata is present, validates it against
  `staff_invites` and either promotes the profile + burns the invite, or
  **raises and aborts the signup**.
- `prevent_role_self_escalation()` — blocks a user changing their own
  `role`, *except* when `auth.uid()` is null (no JWT = dashboard/SQL editor
  = the real owner acting as admin).
- `bootstrap_owner(p_email)` — **admin-only** (EXECUTE revoked from `anon`
  and `authenticated`). Issues an owner invite for an email, or promotes
  that email's existing account to owner. The chicken-and-egg escape hatch
  for creating the first owner; see Decisions.md D33.

**Geography** (PostGIS is in the `extensions` schema):
- `upsert_address(...)` — RPC; builds the PostGIS point from lat/lng
- `set_store_location(lat, lng)` — staff/owner
- `get_delivery_fee(distance)`, `get_delivery_fee_for_point(geography)`,
  `get_delivery_fee_for_coords(lat, lng)`

**Order integrity** (all server-side, client cannot override):
- `compute_delivery_fee_for_order()` — BEFORE INSERT on `orders`; measures
  `ST_Distance(store, address)` and prices it
- `recalculate_order_totals(order_id)` + `order_items_recalculate_totals()`
  — AFTER INSERT/UPDATE/DELETE on `order_items`; keeps subtotal/total exact
- `record_sale_inventory_adjustment()` — AFTER INSERT on `order_items`;
  writes the stock deduction into the ledger
- `restock_on_order_cancellation()` — AFTER UPDATE on `orders`; reverses it
- `apply_inventory_adjustment()` — AFTER INSERT on `inventory_adjustments`;
  the **only** thing that ever writes `products.stock_quantity`

### 3.4 Views

`addresses_with_coords` and `store_settings_with_coords` — `security_invoker`
views that expose `ST_Y(location)`/`ST_X(location)` as plain lat/lng, because
PostgREST cannot serialize a geography column. `security_invoker` means they
respect the caller's RLS rather than the view owner's.

### 3.5 RLS policy shape

Every table has RLS enabled. The pattern is consistent:

- **Catalog** (`categories`, `products`, `product_images`, `offers`,
  `store_settings`, `delivery_fee_tiers`): anyone authenticated reads the
  active rows; `is_staff_or_owner()` writes.
- **Customer-owned** (`addresses`, `orders`, `order_items`,
  `product_inquiries`): customer sees/creates only rows where
  `customer_id = auth.uid()`; staff/owner see and manage all.
- **Staff-only** (`inventory_adjustments`): `is_staff_or_owner()` both ways.
- **Owner-only** (`staff_invites`): `is_owner()`.
- **`profiles`**: read own; staff/owner read all; update own — with the
  escalation trigger preventing self-promotion.

### 3.6 Storage, Realtime, Cron

- **Storage**: public bucket `product-images`. Anyone can read files;
  staff/owner upload/update/delete (storage RLS policies mirror the table
  ones).
- **Realtime**: `product_inquiries` only — added to the `supabase_realtime`
  publication so both apps see chat messages live.
- **pg_cron**: `promote-scheduled-orders`, every minute, flips
  `status='scheduled'` orders to `confirmed` once `scheduled_for <= now()`.

---

## 4. `packages/shared`

### 4.1 Models
Plain immutable classes extending `Equatable`, each with a `fromJson`
factory matching the DB column names exactly (snake_case in, camelCase out).
No code generation.

`Profile` · `UserRole` · `Category` · `Product` · `ProductImage` · `Address` ·
`Order` · `OrderItem` · order enums · `Offer` · `StoreSettings` ·
`DeliveryFeeTier` · `InventoryAdjustment` · `ProductInquiry`

### 4.2 Repositories
All Supabase I/O lives here. Screens never touch `supabase` directly. Split
by *audience and permission*, not strictly by table:

| Repository | Used by | Responsibility |
|---|---|---|
| `AuthRepository` | both | signup (customer/staff), signin, signout, read/update own profile |
| `CatalogRepository` | both | **reads**: categories, products (via `products_with_pricing`), images, offers, store settings, delivery fee |
| `ProductRepository` | staff | **writes**: create/update product, adjust stock, upload image |
| `CategoryRepository` | staff | all categories incl. inactive; create/update/delete, product counts |
| `OfferRepository` | staff | all offers incl. inactive; create, activate/deactivate |
| `StoreRepository` | staff | store location (`set_store_location` RPC), delivery fee tiers |
| `AddressRepository` | customer | list, `upsert_address` RPC, delete |
| `OrderRepository` | both | place delivery order, in-store sale, read orders/items, status + payment updates, `getOrdersForStaff` with filters |
| `ChatRepository` | both | `product_inquiries` realtime stream, send, thread list |
| `PaymentRepository` | customer | Razorpay create-checkout + verify, via Edge Functions |

`CatalogRepository` (reads) and `ProductRepository` (writes) are deliberately
split so the customer app never links write paths it has no permission for.

### 4.3 `LocationService`
The single way either app reads a position. Classifies failure into GPS
off / denied / permanently denied / no fix / unexpected, each with its own
message and an "open settings" affordance where that helps. Times out at
20 s and falls back to the last known position — `getCurrentPosition()`
will otherwise wait indefinitely indoors. See Decisions.md D48.

### 4.4 Shared widgets
`BrandMark` (splash logo + progress ring), `InquiryThreadView` (one
chat conversation, used by both apps), `showSignupCompleteDialog`.

### 4.5 `AppAuthState`
A `ChangeNotifier` holding `status` (loading / unauthenticated /
authenticated) and `profile`. It subscribes to
`AuthRepository.authStateChanges` and refetches the profile on every auth
event. Both apps use it identically; only each app's router redirect differs
in which roles it accepts. It is passed to `go_router` as
`refreshListenable`, so any auth change re-runs routing.

### 4.6 Theme
`AppColors`, `AppTextStyles`, `AppSpacing`, `AppRadius`, `AppTheme.dark` —
a direct transcription of [design.md](design.md). Fonts come from
`google_fonts` at runtime (Hanken Grotesk for headlines/prices, Inter for
body/labels). `formatInr()` in `utils/currency.dart` is the only way prices
get rendered.

---

## 5. customer_app

**Providers** (`main.dart`): `AuthRepository`, `AppAuthState`,
`CatalogRepository`, `AddressRepository`, `OrderRepository`, `ChatRepository`,
`CartController`, `GoRouter`.

| Route | Screen | Notes |
|---|---|---|
| `/splash` | `splash_screen.dart` | shown while `AppAuthState` is loading |
| `/welcome` | `welcome_screen.dart` | pre-auth landing |
| `/login` | `login_screen.dart` | email + password |
| `/signup` | `signup_screen.dart` | name, **mobile**, email, password |
| `/wrong-role` | `wrong_role_screen.dart` | staff/owner who signed in here; signs them out |
| `/home` | `home_screen.dart` | search, categories, offers banner, product grid |
| `/product/:id` | `product_detail_screen.dart` | detail + "Chat for Personalized Order" sheet |
| `/cart` | `cart_screen.dart` | cart, live-location toggle, scheduling, place order |
| `/profile` | `profile_screen.dart` | avatar, name/phone, edit sheet, menu, log out |
| `/orders` | `orders_screen.dart` | order history list |
| `/orders/:id` | `order_detail_screen.dart` | status timeline, items, bill, **Pay Now** |
| `/addresses` | `addresses_screen.dart` | saved addresses list |
| `/address/pick` | `address_pick_screen.dart` | map pin picker + details sheet; add **and** edit both go through it |
| `/categories`, `/category/:id` | `categories_screen.dart` | browse by category |
| `/chat`, `/chat/:productId` | `chat_screen.dart` | inbox of product conversations |

**Gate:** unauthenticated → `/welcome`; authenticated non-customer →
`/wrong-role`; authenticated customer landing on a pre-auth route → `/home`.

`CartController` is in-memory only. There is no `cart` table — the cart
becomes real state only when checkout inserts an order.

## 6. staff_app

**Providers**: `AuthRepository`, `AppAuthState`, `CatalogRepository`,
`ProductRepository`, `OrderRepository`, `OfferRepository`, `GoRouter`.

| Route | Screen | Notes |
|---|---|---|
| `/splash` `/login` `/signup` `/wrong-role` | — | signup requires an invite code |
| `/dashboard` | `dashboard_screen.dart` | sales/pending/low-stock cards + recent sales |
| `/orders`, `/orders/:id` | `orders_screen.dart`, `order_detail_screen.dart` | **the fulfilment queue** — advance status, cancel, mark paid |
| `/in-store-sale` | `in_store_sale_screen.dart` | counter sale; born delivered + paid |
| `/inventory` | `inventory_screen.dart` | product grid, stock steppers, FAB → new product |
| `/categories` | `categories_screen.dart` | create/edit/hide/delete categories |
| `/product/new`, `/product/:id/edit` | `product_form_screen.dart` | shared form, image upload |
| `/offers` | `offers_screen.dart` | list + create + activate toggle |
| `/store-settings` | `store_settings_screen.dart` | shop location + delivery fee bands |
| `/sales` | `sales_screen.dart` | revenue by period and channel |
| `/price-tags` | `price_tags_screen.dart` | printable shelf tags |
| `/chat`, `/chat/:customerId/:productId` | `chat_screen.dart` | customer questions inbox + reply |

`StaffScaffold` is the shell: bottom `NavigationBar` under 900px (Dashboard,
Orders, Inventory, Offers, Settings), a `NavigationRail` above it. The
settings sheet holds the secondary destinations — questions, store settings,
categories, sales, price tags — plus role and log out.

**Gate:** unauthenticated → `/login`; authenticated customer → `/wrong-role`;
staff/owner landing pre-auth → `/dashboard`.

---

## 7. Platform and tooling

- Flutter apps scaffolded `--platforms android` (Play Store + sideloaded
  APK are the only ship targets). A **web target exists in both apps for
  local visual QA only** — `flutter run -d chrome`. It is not shipped.
- Location is **foreground-only**: `ACCESS_FINE_LOCATION` +
  `ACCESS_COARSE_LOCATION` in the customer manifest.
  `ACCESS_BACKGROUND_LOCATION` is deliberately absent and must stay absent.
- Toolchain on this machine is scoop-installed (Flutter, Supabase CLI). Each
  shell invocation is a fresh process — `$env:Path` and
  `SUPABASE_ACCESS_TOKEN` must be set per command.
- `.mcp.json` is project-scoped and contains **no secrets**. Tokens and keys
  live in `~/.claude.json` or environment variables only.

---

## 8. Payment

**Cash on delivery only.** There is no payment gateway and no Edge
Function — `supabase/functions/` is empty. `orders.payment_status` moves
`pending → paid` when staff mark it, which the order detail screen does
automatically on "Mark Delivered" (see Decisions.md D42).

The `razorpay_order_id` / `razorpay_payment_id` columns still exist on
`orders` but are **unused and always null** — left in place rather than
dropped, since dropping columns is destructive and they cost nothing.

## 9. Not built yet

Known gaps, so nobody assumes these exist:

| Gap | Status |
|---|---|
| Phone + OTP auth | phone is captured as profile data only; auth is still email+password. Needs an SMS provider configured in Supabase |
| Customer offers browse | home shows one banner; offers apply to prices, but there's no "all deals" screen |
| Post-order delivery chat | only pre-purchase `product_inquiries` exists |
| Push notifications | nobody is told when an order status changes; the app must be opened |
| App icons | both apps still use the Flutter default — needs source artwork |
| Automated tests | smoke `widget_test.dart` per app; no integration tests |
