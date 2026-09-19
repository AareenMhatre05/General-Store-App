# Privacy Policy — Kavita General Stores

**Last updated:** 16 August 2026

This policy covers the **Kavita General Stores** customer app for Android
and the staff app used inside the shop.

Google Play requires a publicly reachable URL for this policy. Publish
this file somewhere public (GitHub Pages, a Google Site, any static host)
and paste that URL into the Play Console listing — a policy that only
exists in this repository does not satisfy the requirement.

---

## Who we are

Kavita General Stores, a single family-run grocery shop. Questions about
this policy or your data: **kavitageneralstores78@gmail.com**.

## What we collect, and why

| Data | Why | When |
|---|---|---|
| Email address | Your login, and order confirmations | At signup |
| Name | So we know who to hand the order to | At signup, editable later |
| Mobile number | So we can call you about a delivery | At signup, editable later |
| Delivery addresses, including their map coordinates | To deliver to the right place, and to work out the delivery fee from distance to the shop | When you save an address |
| Your device's location | Only to fill in an address you are standing at | Only when you tap "Pin This Location" or "Use current" |
| Orders and their contents | To fulfil, and for the shop's own sales records | When you order |
| Messages you send about a product | So shop staff can answer | When you send one |

We do **not** collect anything for advertising, we do not build profiles,
and we do not track you across other apps or websites.

## Location, specifically

The app requests **foreground location only** (`ACCESS_FINE_LOCATION` /
`ACCESS_COARSE_LOCATION`). It does **not** request background location,
and cannot read your location when it is not open in front of you.

Location is requested at the moment you tap a button that needs it —
never on startup, and never silently. Declining it is fine: you can type
an address instead, though we then cannot calculate a distance-based
delivery fee for it.

## Payments

Orders are **cash on delivery**. The app takes no card, UPI, or bank
details at any point, and no payment processor is involved. We record
only whether an order has been paid for, once the money is handed over.

## Where your data lives

In a **Supabase** project (Postgres database and file storage) hosted on
Supabase's infrastructure. Access is restricted by row-level security:
customers can read only their own profile, addresses, orders, and
messages. Shop staff and the owner can see orders and customer contact
details, because they need those to deliver.

## Who we share it with

Nobody, other than the service providers that make the app work:

- **Supabase** — hosting, database, authentication
- **Google Play** — app distribution

We do not sell data. We do not share it with advertisers.

## How long we keep it

Orders are kept as the shop's business records. Your profile and saved
addresses are kept until you ask us to delete them.

## Your choices

- **See or correct your data:** name, phone and addresses are editable in
  the app under Profile.
- **Delete your account and data:** email
  **kavitageneralstores78@gmail.com** and we will delete your profile,
  addresses, and saved messages. Completed order records are retained as
  required business records, with your contact details removed.
- **Withdraw location permission:** Android Settings → Apps → Kavita
  General Stores → Permissions.

## Children

The app is not intended for children under 13, and we do not knowingly
collect their data.

## Changes

If this policy changes, the date at the top changes with it, and the
updated version is published at the same URL.
