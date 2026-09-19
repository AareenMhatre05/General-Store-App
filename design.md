---
name: Lumina Marketplace
colors:
  surface: '#051424'
  surface-dim: '#051424'
  surface-bright: '#2c3a4c'
  surface-container-lowest: '#010f1f'
  surface-container-low: '#0d1c2d'
  surface-container: '#122131'
  surface-container-high: '#1c2b3c'
  surface-container-highest: '#273647'
  on-surface: '#d4e4fa'
  on-surface-variant: '#cbc3d7'
  inverse-surface: '#d4e4fa'
  inverse-on-surface: '#233143'
  outline: '#958ea0'
  outline-variant: '#494454'
  surface-tint: '#d0bcff'
  primary: '#d0bcff'
  on-primary: '#3c0091'
  primary-container: '#a078ff'
  on-primary-container: '#340080'
  inverse-primary: '#6d3bd7'
  secondary: '#dbb8ff'
  on-secondary: '#3f2160'
  secondary-container: '#573878'
  on-secondary-container: '#caa6ef'
  tertiary: '#bec6e0'
  on-tertiary: '#283044'
  tertiary-container: '#8990a8'
  on-tertiary-container: '#22293d'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#e9ddff'
  primary-fixed-dim: '#d0bcff'
  on-primary-fixed: '#23005c'
  on-primary-fixed-variant: '#5516be'
  secondary-fixed: '#efdbff'
  secondary-fixed-dim: '#dbb8ff'
  on-secondary-fixed: '#29074a'
  on-secondary-fixed-variant: '#573878'
  tertiary-fixed: '#dae2fd'
  tertiary-fixed-dim: '#bec6e0'
  on-tertiary-fixed: '#131b2e'
  on-tertiary-fixed-variant: '#3f465c'
  background: '#051424'
  on-background: '#d4e4fa'
  surface-variant: '#273647'
typography:
  headline-lg:
    fontFamily: Hanken Grotesk
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Hanken Grotesk
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Hanken Grotesk
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-sm:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.01em
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
  price-display:
    fontFamily: Hanken Grotesk
    fontSize: 20px
    fontWeight: '700'
    lineHeight: 24px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  container-padding-mobile: 16px
  container-padding-desktop: 32px
  gutter: 24px
  section-gap: 64px
---

## Brand & Style

The design system is engineered for a tech-forward "Fresh Market" experience, blending professional reliability with high-fidelity digital craftsmanship. The brand personality is innovative, efficient, and premium, targeting a modern consumer who values speed and aesthetic clarity.

The visual style utilizes **Glassmorphism** and **Corporate Modern** influences. By layering vibrant action colors over deep, structured backgrounds, the UI achieves a sense of depth and "object-oriented" physical presence. The emotional response should be one of confidence and technical sophistication, moving away from traditional organic market tropes toward a streamlined, future-facing commerce environment.

## Colors

The palette is anchored by a deep navy foundation to establish a professional, high-fidelity atmosphere.

- **Primary Action (Violet):** Used exclusively for high-priority interactive elements like primary buttons, active states, and critical paths.
- **Surface & Container (Lavender):** A soft, low-opacity lavender is used for cards and grouped content to provide a gentle contrast against the navy background while maintaining a cohesive cool-toned aesthetic.
- **Background (Deep Navy):** The primary canvas for the application, ensuring high-contrast ratios for text readability.
- **Functional States:** Success, Warning, and Error states should be rendered with high-saturation tints that cut through the dark background, utilizing the primary violet as a stylistic anchor for the overall glow and "light-emitting" UI elements.

## Typography

This design system pairs two font families to balance character and utility. **Hanken Grotesk** provides a sharp, contemporary edge for headlines and price displays. **Inter** handles the heavy lifting of body copy and labels with its industry-standard legibility.

Text colors must strictly adhere to accessibility standards against the deep navy background. Primary headings use high-contrast on-surface tones, while secondary body text uses a muted lavender-grey to establish hierarchy.

- **Hierarchy:** Prices are always emphasized using the `price-display` role (Hanken Grotesk, bold) to ensure they are the first thing a user sees on a product card.

## Layout & Spacing

The layout follows a **Fluid Grid** system with fixed maximum widths for desktop viewing to maintain readability.

- **Desktop:** 12-column grid with 24px gutters. Content is centered with a max-width of 1280px.
- **Tablet:** 8-column grid with 20px gutters.
- **Mobile:** 4-column grid with 16px gutters and 16px side margins.

The spacing rhythm is based on an 8px base unit. Component internal padding should favor generous whitespace (e.g., 16px or 24px) to ensure the high-fidelity elements feel "airy" rather than cramped.

## Elevation & Depth

Depth is achieved through **Tonal Layering** and **Glassmorphism**. Rather than traditional black shadows, this design system uses:

1. **Backdrop Blurs:** High-level surfaces like navigation bars and modal overlays use a 20px blur with a semi-transparent lavender tint.
2. **Inner Glows:** Interactive elements like primary buttons feature a subtle 1px inner stroke in a lighter violet to simulate light-emitting surfaces.
3. **Tonal Offsets:** Secondary containers are differentiated from the background by shifting the hex value slightly lighter, rather than using drop shadows.
4. **Tinted Shadows:** When shadows are necessary for high-elevation modals, they use a deep navy tint with 40% opacity to maintain color harmony.

## Shapes

The shape language is consistently **Rounded**, providing a modern and friendly counterpoint to the technical dark theme.

- **Standard Components:** Buttons and input fields use a 0.5rem (8px) radius.
- **Containers:** Product cards and main content sections use a 1rem (16px) radius to emphasize the "fresh" and approachable market feel.
- **Full Radius (Pill):** Used for status badges and category chips.
- **Icons:** Use a 2px stroke weight with rounded terminals to match the typography's geometric curves.

## Components

### Buttons & CTAs
- **Primary Action:** Solid violet with white text. Hover/press states involve a slight scale-up (1.02x) and an increased outer glow.
- **Ghost Action:** Text-only with a lavender border, used for low-priority tasks like "Cancel."

### Cards
- Product cards use a subtle 1px border (`#FFFFFF` at 10% opacity) and a backdrop blur to separate them from the navy background. 16px radius.

### Inputs & Search
- Input fields are darker than the base background with a violet bottom border that expands to a full stroke on focus.
- Search bars are pill-shaped.

### Chips & Badges
- Small, pill-shaped tags used for categories: low-opacity violet background with high-contrast lavender text.
- Status badges use soft background tints for readability (e.g., a teal-cyan tint for success/active, coral for errors, matching the functional-state guidance above).

### Lists
- Clean, borderless rows separated by subtle tonal lines rather than heavy dividers.
