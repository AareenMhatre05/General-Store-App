# Screenshots

The main README references these ten files by exact name. Drop a PNG in
with the matching name and it appears; nothing else needs editing.

## Customer app

| File | Screen | What to have on screen |
|---|---|---|
| `customer-home.png` | Shop | Products visible, a category chip selected, cart badge non-zero |
| `customer-product.png` | Product detail | An item with an offer, so both MRP and the discounted price show |
| `customer-cart.png` | Cart, scrolled to the top | Two or three items with their quantities |
| `customer-checkout.png` | Cart, scrolled to the bottom | Address chosen, delivery fee resolved, total, and both the Place Order and Schedule buttons |
| `customer-orders.png` | Orders | A few orders at different statuses |
| `customer-chat.png` | Chat thread | A short exchange with replies from both sides |

Cart and checkout are the same screen — `cart_screen.dart` holds the
items, the address, the summary and the buttons. Take one shot at the
top and one at the bottom.

## Staff app

| File | Screen | What to have on screen |
|---|---|---|
| `staff-dashboard.png` | Dashboard | Open/closed switch, today's totals, pending deliveries |
| `staff-orders.png` | Orders queue | Several orders, mixed statuses |
| `staff-sales.png` | Sales | A period with real numbers and the profit card |
| `staff-inventory.png` | Inventory | A grid of products with stock steppers |

## Taking them

Android: power + volume-down, then pull the files off the phone.

Crop out the status bar if you like, but keep all ten the same aspect
ratio or the tables in the README will look ragged. Phone-sized portrait
PNGs are right.

A mix of light and dark across the set shows off the theming; the
dashboard looks best in dark.
