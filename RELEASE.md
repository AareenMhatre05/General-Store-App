# Release & configuration checklist

What has to be true outside the code before this ships. Each item says
who does it and what breaks if it's skipped.

---

## 1. Payments — nothing to configure

The shop is **cash on delivery**. There is no gateway, no merchant
account, no keys, no Edge Functions. Staff mark an order paid when they
collect the money (automatic on "Mark Delivered").

## 1b. OpenRouteService key (blocks delivery routing)

The `route` Edge Function is deployed but refuses to run without a key,
so the delivery map shows no route until this is set.

1. Sign up at https://openrouteservice.org/dev/#/signup
2. Request a free **Standard** token in the dashboard
3. Set it:

```bash
supabase secrets set ORS_API_KEY=your-key --project-ref yswvraurldyxatjcuvxg
```

Free tier: 2,000 requests/day, 40/min -- ample, since a route is fetched
when a delivery starts rather than continuously.

**Why it is a server secret and not an app constant:** anything shipped
in an APK can be extracted, and a leaked key lets a stranger spend the
shop's quota. Keeping it server-side also means switching provider
(self-hosted OSRM, Google Directions) needs no app release.

**If skipped:** the map still shows both pins and the straight-line
distance; only the road route and ETA are missing.

## 2. Auth redirect URL (blocks email confirmation on device)

Dashboard → **Authentication → URL Configuration → Redirect URLs**, add:

```
kgs://login-callback
```

Both apps declare this scheme in their AndroidManifest and pass it as
`emailRedirectTo`.

**If skipped:** the confirmation link lands on a browser page instead of
opening the app. The account still gets confirmed, so this is a rough
edge rather than a blocker.

## 3. Custom SMTP (blocks signups at any volume)

Supabase's built-in mailer is rate-limited to a handful of messages per
hour and is explicitly not for production. Dashboard → **Project
Settings → Authentication → SMTP Settings**, point it at any provider
(Resend, Brevo, SendGrid, Gmail SMTP).

**If skipped:** confirmation emails silently stop sending after a few
signups, and new customers cannot log in.

## 4. Store location and delivery fees (blocks correct pricing)

**Location: done.** Set to 19.3473375, 72.8118594 (Pokharni Wadi, Vasai
West) from the owner's Google Maps link. Re-pin from the shop itself via
Settings → Store Settings → **Use My Current Location** if it looks off.

**Fee bands: still empty.** In the **staff app**: Settings → Store
Settings → **+** on Delivery Fees, e.g. 0–1 km ₹20, 1–3 km ₹40, 3 km+ ₹60.

**If skipped:** no band matches, so **every delivery is charged ₹0**.

## 5. Seed the catalog

Staff app → Inventory → Categories first, then products (with photos —
the customer grid looks empty without them).

## 6. App icons — needs artwork from you

Both apps still use Flutter's default icon. Supply a square PNG
(1024×1024, no transparency) and this becomes mechanical:

```bash
flutter pub add --dev flutter_launcher_icons
# configure flutter_launcher_icons in pubspec.yaml, then:
dart run flutter_launcher_icons
```

**If skipped:** Play Store rejects the listing.

## 7. Signing keys

```bash
keytool -genkey -v -keystore %USERPROFILE%\kgs-upload-key.jks \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Copy `android/key.properties.example` to `android/key.properties` in each
app and fill it in. Both are gitignored.

**Back the .jks file up somewhere offline.** Lose it and you can never
update the Play Store listing under the same app again — there is no
recovery process.

## 8. Privacy policy URL

Publish [PRIVACY.md](PRIVACY.md) at a public URL and paste it into the
Play Console. Required because the app requests location.

## 9. Play Console data-safety form

Declare: email, name, phone, location (approximate + precise), purchase
history, and in-app messages. Say data is encrypted in transit, is not
sold, and is not shared for advertising. **No financial data at all** is
collected — the shop is cash on delivery.

## 10. Build

```bash
cd apps/customer_app && flutter build appbundle --release   # Play Store
cd apps/staff_app    && flutter build apk --release         # sideload
```

Install the staff APK by copying it to the device; it is deliberately not
published.

---

## Order of play

1 → 4 → 5 makes the app work end to end for testing.
6 → 10 is only needed to publish.
