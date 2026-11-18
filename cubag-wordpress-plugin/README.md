# CUBAG Portal Connector for WordPress

This plugin connects your WordPress website directly to the live **CUBAG Production API** (`https://cubag-api-server.fly.dev`).

## How to Install on WordPress

1. In WordPress Admin, go to **Plugins** → **Add New** → **Upload Plugin**.
2. Upload `cubag-portal-connector.zip` and click **Install Now**.
3. Click **Activate Plugin**.

*(Alternatively, copy `cubag-portal-connector.php` into your theme's `functions.php` or a snippet in the **WPCode / Code Snippets** plugin).*

---

## Available Shortcodes

Drop any of these shortcodes into any WordPress page, post, Elementor widget, or Gutenberg block:

| Shortcode | What it Displays |
|---|---|
| `[cubag_members]` | Interactive grid of accredited members in Good Standing with real-time search filter and license info. Supports attributes: `[cubag_members limit="20" port="Tema"]` |
| `[cubag_verify_member]` | Instant broker accreditation search box for public/shippers to check if a customs broker is officially in Good Standing. |
| `[cubag_events]` | Cards showing upcoming maritime events, workshops, and stakeholder meetings with dates and locations. Supports: `[cubag_events limit="4"]` |
| `[cubag_news]` | Official CUBAG press releases and trade news with cover images. Supports: `[cubag_news limit="6"]` |
| `[cubag_bulletins]` | Live operational notices and alerts for Tema Port, Takoradi, KIA, Buipe, etc. with status indicator dots. |
| `[cubag_courses]` | CTI (Customs Training Institute) professional courses open for enrollment with fees and cohort start dates. |
| `[cubag_rates]` | Live Bank of Ghana indicative exchange rates bar (USD, EUR, GBP, CNY). |
| `[cubag_portal_summary]` | Executive stats banner (Active Members, Licensed Brokers, Ports, Courses) combined with currency rates. |

---

## Direct REST API Endpoints

If you prefer using pure JavaScript (`fetch`), Gutenberg Custom HTML, or page builders:

- **Base URL:** `https://cubag-api-server.fly.dev/api/v1/public`
- **Members Directory:** `https://cubag-api-server.fly.dev/api/v1/public/members`
- **Verify Member:** `https://cubag-api-server.fly.dev/api/v1/public/verify-member?query={name_or_lic}`
- **Events:** `https://cubag-api-server.fly.dev/api/v1/public/events`
- **News:** `https://cubag-api-server.fly.dev/api/v1/public/news`
- **Port Alerts:** `https://cubag-api-server.fly.dev/api/v1/public/bulletins`
- **Surveys:** `https://cubag-api-server.fly.dev/api/v1/public/surveys`
- **Courses:** `https://cubag-api-server.fly.dev/api/v1/public/courses`
- **Portal Summary:** `https://cubag-api-server.fly.dev/api/v1/public/portal-summary`
- **Interactive Swagger Docs:** `https://cubag-api-server.fly.dev/api/v1/public/docs`
