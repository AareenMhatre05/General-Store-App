# Kavita General Stores

Monorepo for the customer-facing and staff-facing apps, plus the shared
Supabase backend.

## Structure

- `apps/customer_app` — Flutter app (Play Store). Browse, cart, checkout,
  delivery, order chat, scheduled orders.
- `apps/staff_app` — Flutter app (sideloaded APK). Inventory, pricing,
  sales records, offers, store location.
- `packages/shared` — Dart package shared by both apps: data models,
  Supabase client setup, theme.
- `supabase/` — Supabase CLI project: migrations and Edge Functions.

## Getting started

```
cd apps/customer_app && flutter pub get
cd apps/staff_app && flutter pub get
```

Link the Supabase project (run once, from repo root):

```
supabase link --project-ref <your-project-ref>
```
