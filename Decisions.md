# Decisions

The *why* behind every non-obvious choice in this project. Code says what;
this says why, and what the alternative cost would have been. When a decision
here is reversed, edit the entry and add a "Superseded" note — don't delete
it, the reasoning is the point.

Companion docs: [Architecture.md](Architecture.md), [Flow.md](Flow.md).

---

## Foundations

### D1 — Monorepo with two apps and one shared package
**Why:** the customer app and staff app share a backend, a data model, and a
design system, but ship to different audiences through different channels
(Play Store vs sideloaded APK). One repo keeps models and repositories from
drifting; separate app packages keep the staff app's write code out of the
customer binary entirely.
**Rejected:** one app with a role switch — it would ship inventory management
to every customer's phone and make the Play Store listing incoherent.
**Consequence:** `packages/shared` is a local path dependency; a change there
requires re-running `flutter pub get`/analyze in both apps.

### D2 — Supabase as the entire backend; no server of our own
**Why:** a single family store doesn't warrant an API tier to operate and pay
for. Supabase gives auth, Postgres, storage, realtime and cron in one
project.
**Consequence, and this is the important one:** with no server, **RLS is the
only authorization boundary**. Any rule enforced only in Dart is decoration —
the APK is on a customer's phone and can be modified. Every permission
decision must be expressible as a policy. This constraint drives D5, D8, D9
and D10.

### D3 — `provider` for state, `go_router` for navigation
**Why provider:** repositories are plain async methods, not streams or
notifiers. `ChangeNotifier` + `Provider` is the least machinery that does the
job. Riverpod/Bloc would add concepts without solving a problem we have.
**Why go_router:** its `redirect` callback runs on every navigation, which is
exactly the shape of "check session and role before showing anything". The
alternative — an auth check per screen — is the classic way to leak a screen
by forgetting one.
**Consequence:** the router is built **once** via `Provider<GoRouter>`.
Rebuilding it on auth change would lose navigation state and can loop.

### D4 — Migrations only; never change schema in the dashboard
**Why:** the migration files are the schema's source of truth and its
history. A change made in the SQL editor exists nowhere in the repo and is
invisible to the next person (or the next machine).
**Workflow:** `supabase migration new <name>` → write the SQL → `supabase db
push`. Never hand raw SQL over to be pasted manually.
**Exception:** *data* changes an admin legitimately makes (issuing an invite,
promoting the owner account) are dashboard actions, not schema changes —
see D9.

---

## Security and roles

### D5 — Role lives in `profiles`, not in JWT claims
**Why:** the role is read by RLS policies via helper functions
(`is_staff_or_owner()`, `is_owner()`), so it must be queryable in Postgres. A
custom JWT claim would need a token refresh to change and can go stale
against a demoted account.
**Cost:** every policy does a lookup on `profiles`. Acceptable at this scale;
the helper functions are the single place to optimise if it ever isn't.

### D6 — Each app rejects the wrong role client-side, *and* RLS makes it moot
**Why:** the user asked for the delivery app to accept only customers and the
APK to accept only staff/owner. Implemented as a `/wrong-role` screen that
signs the user out. But this is UX, not security — a staff member who forced
their way into the customer app would still only be able to do what their
RLS policies allow.
**Consequence:** never "fix" a permission problem by adding a client-side
check. The fix belongs in a policy.

### D7 — No public self-signup for staff or owner
**Why:** stated requirement — staff and owner accounts are created by the
owner. A public staff signup form would be an open door to the inventory.

### D8 — Invite codes redeemed inside `handle_new_user()`
**Why:** the promotion must happen in the same transaction as account
creation, and it must be impossible to trigger from the client. A
`SECURITY DEFINER` trigger on `auth.users` can validate the invite and set
the role atomically; if the code is bad it raises, and the `auth.users`
insert rolls back with it — no orphaned account.
**Rejected:** promoting after signup from the client (needs a privileged
key on a device — unacceptable), or an Edge Function (more moving parts for
the same result).
**Consequence:** the invite code travels as auth signup metadata
(`raw_user_meta_data`), which is why `AuthRepository.signUpStaff` differs
from `signUpCustomer` only by that one field.

### D9 — `prevent_role_self_escalation()` allows callers with no JWT
**Why (this was a real bug):** the trigger originally blocked any role change
not made by an owner. But the owner acting through the Supabase dashboard or
SQL editor has **no `auth.uid()`** — so `is_owner()` was false and the actual
store owner was locked out of promoting anyone, including bootstrapping the
very first owner account.
**Fix:** the trigger's condition now starts with `auth.uid() is not null and
…`, so a null-JWT admin context passes through. Anyone acting *through the
apps* is still blocked from changing their own role.
**Trade-off:** accepted — anything with dashboard/service-role access is
already fully privileged; the trigger was never a defence against that.

### D10 — Money and stock are computed by triggers, never sent by the client
**Why:** `delivery_fee_amount`, `subtotal_amount`, `total_amount` and
`distance_meters` are set by `BEFORE INSERT` / `AFTER INSERT` triggers, and
customers have no UPDATE policy on `orders`. If the client sent these, a
modified APK could order groceries for ₹0 with free delivery.
**Consequence:** `OrderRepository.placeDeliveryOrder` deliberately sends only
what a client legitimately controls (address, items, schedule, notes), then
re-reads the row to get the authoritative totals. Prices shown in the cart
before checkout are display-only estimates.

### D11 — Stock changes only through the `inventory_adjustments` ledger
**Why:** `products.stock_quantity` is a cached running total. Every change —
a sale, a cancellation restock, a manual staff correction — inserts a ledger
row, and `apply_inventory_adjustment()` is the only thing that updates the
cached column. That gives a full audit trail for free and makes
"why is this count wrong?" answerable.
**Consequence:** never `UPDATE products SET stock_quantity`. Insert an
adjustment.

### D12 — Only the anon key ships; secrets never enter the repo
**Why:** the anon key is designed to be public and carries no privileges
beyond what RLS grants. The `service_role` key and personal access tokens
bypass RLS entirely and must never appear in a committed file, including
`.mcp.json` (which is project-scoped and therefore shared).
**Practice:** local secrets go in `~/.claude.json` or environment variables.
Any token that has been pasted into a chat or a log is considered burned and
should be rotated.

---

## Data model

### D13 — `security_invoker` views for geography columns
**Why:** PostgREST can't serialize a PostGIS `geography` value, so
`addresses` and `store_settings` are read through `addresses_with_coords` /
`store_settings_with_coords`, which expose `ST_Y`/`ST_X` as plain lat/lng.
`security_invoker` makes the view respect the **caller's** RLS rather than
the view owner's — without it, the view would quietly become a way around
the policies on the underlying table.
Writes go through the `upsert_address` / `set_store_location` RPCs for the
same serialization reason, in reverse.

### D14 — Distance casts must be explicit (`::numeric`)
**Why (build failure, now fixed):** `ST_Distance` returns `double precision`,
but `get_delivery_fee` takes `numeric`. The first `db push` failed on the
implicit cast.
**Rule:** cast explicitly at every PostGIS ↔ numeric boundary.

### D15 — `product_inquiries` is pre-purchase Q&A only
**Why:** the Stitch product-detail design has a "Chat for Personalized Order"
button with no table behind it. Rather than build a general messaging system
speculatively, the table covers exactly the designed feature: one
customer + one product thread, staff/owner can see and reply to all.
**Explicitly not covered:** post-order delivery chat. That is a different
shape (per-order, time-bounded, involves a delivery person) and gets its own
design when it's actually needed.
**Consequence:** it's the only table on the `supabase_realtime` publication —
realtime is enabled where it's genuinely needed, not by default.

### D16 — Scheduled orders promoted by `pg_cron`, not by the client
**Why:** an order scheduled for 6pm must enter the staff queue at 6pm whether
or not anyone has the app open. A one-line-a-minute `UPDATE` is the whole
implementation.
**Deliberately minimal:** it only flips the status. Notifying staff or the
customer in real time is a later layer, once that workflow is designed.

### D17 — Cart is in-memory; there is no `cart` table
**Why:** a cart is ephemeral session state for this kind of store. Persisting
it means sync rules, staleness against price changes, and a table to
maintain, for a feature nobody asked for.
**Consequence:** closing the app empties the cart. Revisit only if it's
actually a complaint.

### D18 — Reads and writes split across `CatalogRepository` / `ProductRepository`
**Why:** the customer app should not even link code paths it has no
permission to execute. Reads that both apps need live in `CatalogRepository`;
staff-only writes live in `ProductRepository` and `OfferRepository`, which
the customer app doesn't register as a provider.

---

## UI

### D19 — Lumina Marketplace, not Fresh Market System
**Why (a correction):** the Stitch project has two saved design systems.
`design.md` was first written from "Fresh Market System" (green/orange,
light). Checking each screen's actual Tailwind config showed **7 of 8 real
screens were built with "Lumina Marketplace"** (deep navy/violet, dark,
Hanken Grotesk + Inter), and the user confirmed that is the intended one.
`design.md` was rewritten to match.
**Consequence:** `design.md` is the single source of truth. UI colours,
spacing and type are never invented in a screen file — they come from
`AppColors` / `AppTextStyles` / `AppSpacing` / `AppRadius`, which mirror it.

### D20 — ₹ everywhere, "K.G.S" in tight spaces
**Why:** the Stitch mockups use `$` and spell out "Kavita General Stores",
which overflows compact headers. One helper, `formatInr()`, is the only way
a price is rendered — so there is no way for a stray `$` to reappear. The
full name stays where the design gives it room.

### D21 — Fonts from `google_fonts` at runtime, not bundled
**Why:** the app requires a network connection for Supabase anyway, so
runtime font fetching costs nothing in practice and keeps the APK smaller.
**Dropped:** JetBrains Mono, which the Lumina style guide mentions for price
alignment but **no actual screen ever uses** — every real screen sets
Hanken Grotesk for prices. Matching what was built beat matching the prose.

### D22 — Capture `context.read<T>()` into a local before any `await`
**Why:** using a `BuildContext` after an await is unsafe if the widget was
disposed meanwhile — `use_build_context_synchronously` flags it. This came up
repeatedly (cart, dashboard, offers, profile).
**Pattern:** read the providers you need *before* the first `await`, then use
the locals afterwards. Applied consistently; treat any new occurrence the
same way rather than suppressing the lint.

### D23 — A web target exists in both apps, for local QA only
**Why:** no Android emulator/cmdline-tools on this machine, and screens need
to be *looked at*, not just analyzed. `flutter run -d chrome` gives that.
**Boundary:** web is never a ship target; Play Store + sideloaded APK are.
Nothing may depend on web-only behaviour.

### D24 — GUI click automation was abandoned as unreliable
**Why (an incident):** a simulated click intended for a Chrome button landed
on the host IDE's chat input, because window focus had silently shifted. It
was caught immediately and nothing was submitted, but coordinate-based mouse
automation clearly cannot be trusted here.
**Rule:** screenshot-only verification, no synthetic clicking. And do not
screen-capture at all while the machine is in active use — a full-screen grab
catches whatever the user has open, which is theirs, not ours.

---

## Product behaviour

### D25 — Location is foreground-only, requested at point of use
**Why:** stated requirement, and Play Store policy treats background location
as a high-scrutiny permission needing separate justification. The manifest
declares `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` and
deliberately **omits** `ACCESS_BACKGROUND_LOCATION`.
**Consequence:** permission is requested when the customer toggles "Share
Live Location" at checkout — not at app start. Do not add the background
permission to fix a "location stopped updating" bug; that is the intended
behaviour.

### D26 — Checkout upserts an implicit "Current Location" address
**Why:** the Stitch checkout screen has no address form at all, only a
location toggle, and full address-book management is Phase 2. To place real
orders now, toggling location captures the position and silently upserts a
single address labelled "Current Location" with placeholder city/pincode.
**This is a product-behaviour shortcut, flagged as such** — not an oversight.
When the address book lands, this path should become "choose a saved address
or use current location", and the placeholder city/pincode should go away.

### D27 — Signup collects a mobile number, but auth stays email+password
**Why:** the user wanted Zomato/Blinkit-style signup, where phone is primary
and email optional. Real phone+OTP auth needs an SMS provider (Twilio, MSG91,
…) configured in the Supabase dashboard — an external cost and account the
owner has to set up. So the field and the schema plumbing landed first
(`handle_new_user()` reads `phone` from signup metadata), and the auth
mechanism swap waits for that decision.
**Status: deliberately half-done.** `profiles.phone` is populated and
editable; it is not yet a credential.

### D28 — Profile is a full screen, not a bottom sheet
**Why:** the original profile was a sheet with a log-out button. Blinkit and
Zomato treat the profile as a destination with identity at the top and a menu
of sub-sections. The new `/profile` screen matches that, and gives the Phase
2 items (orders, addresses, help) a natural home instead of nowhere.

### D29 — Placing an order lands on that order's detail page
**Why:** dropping the customer back on Home after checkout gives no
confirmation of what was just ordered. Every comparable app shows the order.
Now that order history exists, `placeDeliveryOrder` returns the created
order and the screen navigates to `/orders/{id}`.

### D30 — Staff/customer order lists are the *same query*
**Why:** `getMyOrders()` and `getAllOrders()` are literally the same SELECT;
RLS decides whether it returns one customer's orders or all of them. Two
methods exist only because the intent reads differently at each call site.
**Consequence:** don't add a `customer_id` filter in Dart "to be safe" — it
would silently break the staff view, and it isn't what protects the data.

### D31 — Dashboard aggregates are computed client-side
**Why:** at family-store volume, fetching orders and summing in Dart is
simpler than maintaining SQL views, and avoids a schema change per metric.
**Trip-wire:** if order volume grows enough that the dashboard feels slow,
these move to SQL views or RPCs. That's the signal to watch for.

---

### D33 — The first owner is bootstrapped by an admin-only SQL function
**Why:** `staff_invites` is guarded by `is_owner()`, so an owner is needed to
create the invite that makes someone an owner — the first one can't come
through the normal path (D8). `public.bootstrap_owner(p_email)` is that entry
point: called from the SQL editor or service role, it either issues an owner
invite for a not-yet-registered email, or promotes an existing account
directly (which a second signup couldn't do — it would fail with "user
already registered").
**Why the email isn't in the migration:** the function takes it as an
argument, so no personal address or invite code is committed to the repo.
**Security note (a real finding, fixed in a follow-up migration):** the
function is `SECURITY INVOKER` and `revoke execute … from public` was applied
— but Supabase grants EXECUTE on public-schema functions to `anon` and
`authenticated` *explicitly*, and an explicit grant survives a revoke from
`PUBLIC`. So it was still callable by any signed-in user. A client call would
have failed anyway (no SELECT on `auth.users`; RLS on `staff_invites`), but a
function that hands out the owner role shouldn't be reachable at all.
`revoke execute … from anon, authenticated` is now applied and verified.
**Rule for any future privileged function:** revoke from `anon` and
`authenticated` by name, and verify with `has_function_privilege` — don't
assume revoking from `PUBLIC` covered it.

### D34 — Signup ends at the login screen, not signed in
**Why:** requested — after creating an account the user should land on the
login screen and sign in deliberately, rather than being dropped into the app
(or, as it behaved before, left sitting on the signup form with no feedback).
**The catch:** Supabase's `signUp` returns a **session** when email
confirmation is disabled, so the new user is authenticated immediately and
the router redirect would skip `/login` entirely. So the screen checks
`response.session` and explicitly signs out when one came back. When
confirmation *is* enabled there's no session to undo, and the message tells
the user to confirm their email first — both configurations work without a
code change.
**Applied to both apps** (customer and staff), since the flow is identical
and leaving one inconsistent would be surprising.
**Consequence:** signup no longer relies on the auth-state-change redirect to
navigate. It is now the one place that navigates explicitly after an auth
call.

### D35 — Signup confirmation is a dialog; login names the real failure
**Context:** the project has Supabase's "Confirm email" setting **on** —
verified from `auth.users`: real signups have a `confirmation_sent_at` and
were confirmed a minute or two later. (Users created from the dashboard are
auto-confirmed, which is why the owner account has no confirmation email.)
**Why a dialog, not a SnackBar:** with confirmation on, the user *cannot log
in* until they open the emailed link. A message that fades after four seconds
is the wrong carrier for an instruction the account depends on. The dialog is
`barrierDismissible: false` with a single "Go to Login" action, and it names
the address the link went to.
**Why login distinguishes the failure:** an unconfirmed user was being told
"Check your email and password", sending them to re-check a password that was
correct. `AuthRepository.signIn` now catches gotrue's `AuthException` and
rethrows a `SignInException` carrying a `SignInFailure` — so screens act on a
domain enum and Supabase's exception types stay inside the repository layer,
per the rule in Architecture.md.
**Accepted trade-off:** distinguishing the two does reveal that an address is
registered. For a neighbourhood store, a legitimate customer understanding
why they can't log in is worth more than that.
**Operational note:** Supabase's built-in SMTP is rate-limited (single-digit
emails per hour on the free tier). Creating several test accounts in a row
will silently stop sending. Real use needs custom SMTP configured in the
dashboard — a project setting, not a code change.

---

## Closing the functional gaps (2026-08-16)

### D36 — Staff order fulfilment is a top-level destination
**Why:** `updateOrderStatus()` and `createInStoreSale()` existed in the
repository but **nothing called them** — an order could be placed and never
progressed, so the delivery loop didn't close. Orders is now the second nav
destination, not something buried in a menu, because it's the screen the shop
lives in daily.
**Design:** the default filter is "Needs action" (everything not delivered or
cancelled), since the working question is "what do I have to do now", not
"show me all orders ever".
**Marking delivered also settles a cash order**, because handing goods over
in person is the payment. Staff can still mark paid separately for a partial
or early payment.

### D37 — Offers apply server-side, and unit_price is no longer client input
**Why:** two problems with one cause. Offers were decorative — nothing ever
reduced a price by one. And `order_items.unit_price` was whatever the client
sent, so a modified client could have bought anything for ₹0.01, which
contradicts D10's rule that money is computed server-side.
**Fix:** `best_offer_for_product()` picks the single applicable offer
(specificity first — product beats category beats store-wide; ties go to the
bigger discount), `effective_unit_price()` applies it, and a BEFORE INSERT
trigger on `order_items` stamps that price on every line.
**Staff can override, customers cannot:** an in-store sale sometimes goes out
at a negotiated price and the person entering it is trusted, so a staff-sent
price is honoured. A customer-sent one is discarded.
**Reading side:** `products_with_pricing`, a `security_invoker` view carrying
`effective_price` and the offer's title, so no client re-implements the
discount rules. `Product.sellingPrice` falls back to the list price when the
row came from the table rather than the view.

### D38 — Store location and fee tiers get a screen, not a map
**Why:** with `store_settings.location` null, `ST_Distance` returns null and
**every delivery is priced ₹0** — a silent, invisible failure. It needed a UI.
**No map widget:** an embedded Google Map needs a billed API key. For one
fixed shop, "stand at the counter and press Use My Current Location" is more
accurate and free; manual lat/lng covers the rest. The screen shows a red
warning while the location is unset, so the silent failure is now loud.

### D39 — Addresses are pinned, not geocoded
**Why:** the delivery fee is distance-based, so every address needs
coordinates. There's no geocoding service wired up (another billed API), so
an address is pinned by physically being there. Checkout keeps "Use current"
as a one-tap path, and the implicit "Current Location" row from D26 is now
one option among saved addresses rather than the only mechanism.
**Supersedes the shortcut half of D26.**

### D40 — Razorpay: the server decides the amount and whether it was paid
> **SUPERSEDED by D42 (2026-08-16).** Razorpay was removed the same day in
> favour of cash on delivery. The reasoning is kept because it is the design
> to return to if online payment is ever revisited.

**Why:** two independent trust boundaries. The client says *which* order to
pay for, never how much — `razorpay-create-order` reads `total_amount` from
the row, under the caller's own RLS, so it can't create a payment for someone
else's order. And `razorpay-verify-payment` recomputes Razorpay's HMAC over
`order_id|payment_id` with the key secret before marking anything paid, using
a constant-time compare; without that check, a client could simply claim
success.
**Only the Edge Function may mark an order paid** — customers deliberately
have no UPDATE policy on `orders`, so it uses the service role, and only
after the signature verifies.
**Verification failure after a successful charge is treated specially:** the
customer is told to contact the shop rather than "payment failed", because
money may genuinely have left their account.
**Payments are Android-only:** the plugin has no web implementation, so the
service checks `kIsWeb` and explains instead of crashing inside the sheet.

### D41 — Release signing falls back to debug keys
**Why:** `key.properties` is gitignored (a committed keystore is a keystore
anyone can ship updates with), so a fresh clone has no signing config. Rather
than failing the build, the release type falls back to debug keys — local
`flutter run --release` keeps working, and a Play Store build requires the
real keystore by definition, since Play rejects debug-signed uploads.
**R8 is enabled for the customer app**, with explicit `-keep` rules for
Razorpay: it drives callbacks by reflection, and without those rules the
release build compiles and then crashes when the payment sheet opens.

### D42 — Cash on delivery only; Razorpay removed
**Why:** the owner's call — a neighbourhood grocery takes cash at the door,
and an online gateway brings a merchant account, KYC, settlement cycles,
refund handling and a per-transaction cut for no benefit the shop wants.
**Removed:** both Edge Functions (deleted from the project, not just the
repo), `PaymentRepository`, the `razorpay_flutter` dependency, the checkout
service, and the "Pay Now" button. The customer now sees a plain "pay in
cash when your order arrives" note on an unpaid order.
**Kept deliberately:**
- `orders.payment_status` — still meaningful for cash: it records whether
  the money has actually been collected, which the sales screen totals as
  "still unpaid".
- `razorpay_order_id` / `razorpay_payment_id` columns — now always null.
  Left in place because dropping columns is destructive and they cost
  nothing; if online payment ever returns, D40 describes how it worked.
**Consequence:** an order's status can now reach `delivered` while
`payment_status` is still `pending` only if staff explicitly skip the
prompt — marking delivered settles it by default (D36).

---

## Bugs the first device test exposed (2026-08-16)

Everything below had passed `flutter analyze` and worked in the browser.
None of it survived contact with a phone. Recorded because the *class* of
each bug is worth recognising again, not just the fix.

### D43 — Release builds need INTERNET declared in `src/main`
Flutter's template declares `android.permission.INTERNET` only in
`src/debug/` and `src/profile/`. A release APK therefore has **no network
access at all**, and every Supabase call fails at the socket. It presented as
"wrong password" because the login screen's catch-all blamed credentials.
**Fixed** by declaring it in `src/main/AndroidManifest.xml` in both apps, and
by classifying network failures separately (`SignInFailure.network`) so a
server that was never reached can't be reported as a bad password.

### D44 — `orders.customer_id` was never sent, so checkout could not work
The column has no default; the RLS insert policy is `customer_id =
auth.uid()`; the table CHECK requires it for delivery orders. The client sent
everything except that. **Every order was rejected**, reported as "could not
place the order, please try again".
**Fixed** by sending it explicitly — safe, because RLS rejects any value but
the caller's own id — and in-store sales deliberately keep it null so a
counter sale isn't attributed to the staff member ringing it up.
**Also:** `placeDeliveryOrder` now throws `OrderException` carrying the
server's message instead of the screen printing a generic retry prompt. A
rejected write should say which rule rejected it.

### D45 — `upsert_address()` returned a row the client could not parse
It returned `public.addresses`: the raw table row, carrying a PostGIS
`location` column and **no latitude/longitude**. `Address.fromJson` reads
`json['latitude']`, so saving an address always threw — masked by a "could
not save, try again" catch. It had never worked.
**Fixed** by returning `public.addresses_with_coords`, the same shape the
read path uses, so one parser serves both. The function also enforces one
default address per customer now.
**Lesson:** a view for reads and a function for writes must agree on shape.
Returning the table type from a write path silently breaks that contract.

### D46 — A widget painted outside its parent receives no taps
The product card's fixed square image overflowed its grid cell, pushing the
price row and the **+** button outside the card's bounds. Flutter paints
overflow (with debug stripes that release builds hide) but does not hit-test
it, so "add to cart" was visible and dead.
**Fixed** by making the image `Expanded` — it takes the space left over
rather than demanding a square — and giving the cells more height.
**Lesson:** "the button does nothing" on a laid-out-by-constraint UI is a
layout bug until proven otherwise.

### D47 — `go()` replaces the stack; drill-downs must `push()`
Every navigation used `context.go()`, which *replaces* the route stack. So
back arrows did nothing and the Android back key exited the app from any
screen — there was never a previous route to return to.
**Rule now:** `push` for anything the user should be able to back out of
(product, cart, orders, profile, categories, chat, addresses); `go` only for
switching root context (auth flow, resetting to Home after checkout). The
bottom-nav destinations push too, because Home is the only screen that
carries the nav bar and must stay underneath them.

### D48 — Location failures are classified, not lumped together
`getCurrentPosition()` was called with no time limit, so indoors it waits
forever for a fix that never arrives, and the UI spins with permission
already granted. All failure modes shared one "check permissions" message,
which made a device-only problem impossible to diagnose remotely.
**Fixed** with a shared `LocationService`: 20-second timeout falling back to
the last known position, `LocationAccuracy.high` (settles far faster than
`best`), and five distinct outcomes — GPS off, denied, permanently denied,
no fix, unexpected — each with its own advice and an "Open settings" button
where that is the actual remedy.

### D49 — Address capture is a map pin, not a form
**Supersedes the manual-entry half of D39.** Typing an address cannot produce
coordinates, and coordinates are what the delivery fee is computed from.
Following Zomato/Blinkit: a fixed centre pin with the map moving underneath
(easier one-handed than dragging a marker), reverse-geocoded live into a
readable place name, then a details sheet for what a map cannot know — flat
number, landmark — with a Home/Work/Other tag.
**Why OpenStreetMap via `flutter_map`, not Google Maps:** no API key, no
billing account, no per-load cost. Reverse geocoding uses the platform's
built-in geocoder for the same reason. Both are free at this scale, and the
shop should never get a bill for someone browsing addresses.
**Version note:** `geocoding` 3.x pins its Android module to compileSdk 33
while its own AndroidX dependencies demand 34+, which fails the release build
on AAR metadata; 5.x fixes that but replaced the top-level
`placemarkFromCoordinates()` with an instance API.

---

## Process

### D32 — Documentation is part of the work
**Why:** this project is built across many sessions, and context is lost
between them. `Architecture.md` says what exists, `Flow.md` says how it runs,
`Decisions.md` says why — so nothing has to be re-derived from the code, and
nothing gets changed blind.
**Practice:** when a decision is made or reversed, it gets an entry here in
the same change, not later.
