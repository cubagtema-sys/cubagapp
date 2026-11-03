# CUBAG Public REST API — Integration & Developer Handover Guide

> **Document Version:** 1.0.0  
> **Target Audience:** External Website Developers, Portal Engineers, Regulatory Integrators  
> **Production API Base URL:** `https://cubag-api-server.fly.dev`  
> **Interactive Swagger Documentation:** [`https://cubag-api-server.fly.dev/api/v1/public/docs`](https://cubag-api-server.fly.dev/api/v1/public/docs)  
> **OpenAPI 3.0 Specification:** [`https://cubag-api-server.fly.dev/api/v1/public/openapi.json`](https://cubag-api-server.fly.dev/api/v1/public/openapi.json)  
> **Postman Collection:** `CUBAG_Public_API.postman_collection.json` (root of repository)

---

## 1. Architectural Overview

The **Customs Brokers Association Ghana (CUBAG) Public REST API** is an independent, highly-optimized service decoupling the CUBAG backend and mobile database from external public-facing websites (WordPress, Next.js, Webflow, static frontends, or partner customs portals).

### Key Architectural Characteristics
- **Zero Authentication Required for Public Routes:** Public consumers do not require JWTs or API keys.
- **Aggregated Composite Endpoint (`portal-summary`):** External homepages can retrieve complete public state (statistics, Bank of Ghana exchange rates, news, bulletins, upcoming events, CTI courses, and ports) in a **single HTTP round-trip**.
- **Edge & Redis Caching with Stampede Protection:** Composite endpoints are cached for 60 seconds (`X-Cache: HIT|MISS`, `Cache-Control: public, max-age=60`). Cache regeneration is guarded by a single-flight mutex to protect the primary database against traffic spikes.
- **Cryptographic Enumeration Prevention:** Verification and tracking lookups require high-entropy cryptographic tokens. Predictable sequential identifiers (`?ref=1`, `?ref=TXN-000001`) are rejected.
- **Strict Privacy / Non-Disclosure:** Public endpoints sanitize PII. Complainant contact details, private notes, and internal database primary keys are never exposed.

---

## 2. Global Conventions & CORS

### Base URLs
- **Production:** `https://cubag-api-server.fly.dev`
- **Canonical API Root:** `/api/v1/public` (also aliased under `/api/public` for convenience)

### CORS Policy
- **Allowed Origins:** `*` (Wildcard enabled to support cross-origin browser requests, headless Next.js frontends, and mobile WebViews).
- **Allowed Headers:** `Authorization`, `Content-Type`, `Accept`, `X-Requested-With`, `Cache-Control`, `X-Tracking-Token`, `X-API-Key`.
- **Allowed Methods:** `GET`, `POST`, `OPTIONS`.

### Rate Limiting & HTTP 429
Public endpoints enforce per-IP rate limiting based on the validated edge IP (`Fly-Client-IP` / `CF-Connecting-IP` / `X-Forwarded-For`).
When rate limits are exceeded, the API returns **HTTP 429 Too Many Requests** with standard `Retry-After` headers:

```json
{
  "success": false,
  "message": "Too many requests. Please wait a moment and try again.",
  "error": "Rate limit exceeded",
  "retry_after_seconds": 45
}
```

| Endpoint Scope | Limit | Window |
|---|---|---|
| `/portal-summary` & `/stats` | 60 requests | 60 seconds |
| `/verify-member` | 30 requests | 60 seconds |
| `/verify-receipt` | 25 requests | 60 seconds |
| `/complaints` (Submission) | 5 requests | 3600 seconds (1 hour) |
| `/complaints/track/{id}` | 20 requests | 60 seconds |
| Publications, Events, Surveys | 40 requests | 60 seconds |

---

## 3. Core API Endpoints

### 3.1 Consolidated Homepage: `GET /api/v1/public/portal-summary`
The recommended starting point for the public website homepage. Returns all dynamic landing elements in one request.

**Headers Returned:**
- `X-Cache: HIT` (served from cache) or `X-Cache: MISS` (freshly assembled)
- `Cache-Control: public, max-age=60`

**Response Structure (HTTP 200):**
```json
{
  "success": true,
  "stats": {
    "active_members": 8,
    "licensed_brokers": 7,
    "operating_ports": 6,
    "cti_courses": 3
  },
  "exchange_rates": {
    "usd_ghs": 15.00,
    "eur_ghs": 16.00,
    "gbp_ghs": 19.00,
    "cny_ghs": 2.00,
    "source": "Bank of Ghana Indicative Rates",
    "effective_date": "2026-10-13T08:03:41.840853"
  },
  "latest_news": [
    {
      "id": 1,
      "title": "CUBAG & ICUMS 2.0 Joint Framework on Port Clearance Expedited Process",
      "summary": "The Customs Brokers Association Ghana in partnership with GRA Customs Division...",
      "image_url": "https://images.unsplash.com/photo-1578575437130-527eed3abbec?auto=format&fit=crop&w=800&q=80",
      "source": "CUBAG Official Press",
      "published_at": "2026-10-31T18:00:00"
    }
  ],
  "bulletins": [
    {
      "id": 1,
      "port_name": "Tema Port",
      "code": "TMP",
      "status": "Normal Operations",
      "notice": "MPS Terminal 3 gates fluid. Average truck turnaround under 45 minutes.",
      "status_color": "green"
    }
  ],
  "upcoming_events": [
    {
      "id": 1,
      "title": "Annual Maritime Logistics & Customs Clearance Summit 2026",
      "description": "National convention bringing together GPHA, GRA Customs Division, and licensed freight forwarders.",
      "date": "2026-11-20",
      "time": "09:00 AM",
      "location": "Tema Port Maritime Centre",
      "capacity": 350
    }
  ],
  "cti_courses": [
    {
      "id": 1,
      "title": "Freight Forwarding Fundamentals & HS Classification",
      "start_date": "15 Dec 2026",
      "duration": "4 Weeks",
      "mode": "In-Person / Online",
      "fee": 850.0,
      "currency": "GHS",
      "cohort_status": "Enrollment Open",
      "description": "Comprehensive tariff classification under the WCO Harmonized System.",
      "accredited": true
    }
  ],
  "ports": [
    { "id": 1, "name": "Tema Port", "code": "TMP" },
    { "id": 2, "name": "Takoradi Port", "code": "TKD" },
    { "id": 3, "name": "Accra International Airport (KIA)", "code": "ACC" },
    { "id": 4, "name": "Aflao Border Post", "code": "AFL" },
    { "id": 5, "name": "Elubo Border Post", "code": "ELB" },
    { "id": 6, "name": "Paga Border Post", "code": "PAG" }
  ],
  "timestamp": "2026-11-02T21:40:00Z"
}
```

---

### 3.2 Member Verification: `GET /api/v1/public/verify-member`
Allows consumers, shippers, and port authorities to verify whether a customs broker is officially accredited and in Good Standing.

**Query Parameters:**
- `query` (string, required, minimum 3 chars): CUBAG Membership number (`CUBAG-2026-0008`), Customs Broker license (`CUBAG-LIC-2026-0008`), or registered company name.

**Security Controls:**
- Sequential database IDs (e.g. `?query=1`) are strictly rejected.
- Returns only approved public accreditation attributes. Never exposes member emails, phone numbers, or residential addresses.

**Response (HTTP 200 - Verified):**
```json
{
  "verified": true,
  "standing_status": "Good Standing",
  "good_standing": true,
  "company_name": "ANTWI NYAME ENTERPRISE",
  "membership_number": "CUBAG-2026-0008",
  "license_number": "CUBAG-LIC-2026-0008",
  "member_category": "Corporate Member",
  "primary_port": "Tema Port",
  "valid_until": "31 Dec 2026",
  "verified_at": "02 Nov 2026"
}
```

**Response (HTTP 200 - Not Found):**
```json
{
  "verified": false,
  "message": "No verified CUBAG member found matching those credentials. Please check the membership or license number."
}
```

---

### 3.3 Receipt Verification: `GET /api/v1/public/verify-receipt`
Intended for QR code scanners on official payment receipts, physical clearance documents, and annual fee certificates.

**Query Parameters:**
- `token` or `ref` (string, required): 128-bit cryptographic verification token (minimum 16 chars).
- `amount` (number, optional): If provided, validates that the payment amount matches expected figures.

**Security Controls:**
- Predictable/sequential lookups (`ref=1` or `ref=TXN-000001`) are rejected with HTTP 400.
- PII sanitization: Never exposes payer name, banking coordinates, momo numbers, or internal database IDs.

**Response (HTTP 200):**
```json
{
  "verified": true,
  "verification_token": "943d21ee5518af43ba4a9fa039b173ef",
  "status": "completed",
  "amount": 1.0,
  "currency": "GHS",
  "description": "Annual Practicing License Renewal",
  "issued_at": "2026-10-15T12:00:00",
  "paid_at": "2026-10-15T12:05:00",
  "issuing_authority": "Customs Brokers Association Ghana (CUBAG)",
  "verified_at": "2026-11-02T21:40:00.123456"
}
```

---

### 3.4 Public Grievance Submission: `POST /api/v1/public/complaints`
Allows importers, exporters, and licensed brokers to file grievances regarding demurrage disputes, ICUMS delays, or port misconduct.

**Request Body (JSON):**
```json
{
  "name": "Kwame Asante",
  "email": "kwame.asante@example.com",
  "phone": "+233244000111",
  "category": "Port Demurrage Dispute",
  "port": "Tema Port",
  "target_entity": "Shipping Line Agency",
  "subject": "Excess Detention Charge Assessment",
  "description": "Container released within free days but detention invoices billed at gate out.",
  "hp_field": ""
}
```

**Anti-Spam Honeypot:**
- Frontend forms must render an invisible input field named `hp_field` (hidden via CSS `display:none`).
- Legitimate human users leave this blank. Automated spam bots populate it. Any submission with a populated `hp_field` is rejected.

**Response (HTTP 201 Created):**
```json
{
  "success": true,
  "message": "Complaint lodged successfully. Keep your tracking token secure; both complaint_id and tracking_token are required to view grievance status.",
  "complaint_id": "CMP-2026-80069",
  "tracking_token": "de64c421cadcb0cab55346be70171c1a",
  "data": {
    "complaint_id": "CMP-2026-80069",
    "category": "Port Demurrage Dispute",
    "port": "Tema Port",
    "status": "Received",
    "created_at": "2026-11-02T21:40:00Z"
  }
}
```

---

### 3.5 Grievance Status Tracking: `GET /api/v1/public/complaints/track/{complaint_id}`
Allows a complainant to check the live secretariat resolution timeline.

**Security Requirement:**
- Requires the **128-bit cryptographic tracking secret token** issued at submission.
- Pass via query parameter: `?token=de64c421cadcb0cab55346be70171c1a` or via HTTP Header: `X-Tracking-Token: de64c421cadcb0cab55346be70171c1a`.
- Without a valid token, returns **HTTP 401 Unauthorized** or **HTTP 404 Not Found**.

**Response (HTTP 200):**
```json
{
  "success": true,
  "data": {
    "complaint_id": "CMP-2026-80069",
    "category": "Broker Misconduct",
    "port": "Accra International Airport",
    "status": "Received",
    "created_at": "2026-11-02T21:40:00Z",
    "updated_at": "2026-11-02T21:40:00Z",
    "timeline": [
      {
        "step": 1,
        "title": "Complaint Lodged",
        "desc": "Formal grievance logged into CUBAG Central Secretariat Registry.",
        "done": true,
        "active": true,
        "date": "02 Nov 2026, 09:30 PM"
      },
      {
        "step": 2,
        "title": "Secretariat Review",
        "desc": "Assigned to the Grievance & Disciplinary Standing Committee for preliminary merit assessment.",
        "done": false,
        "active": false,
        "date": "Pending"
      },
      {
        "step": 3,
        "title": "Port & Stakeholder Investigation",
        "desc": "Evidence verification and stakeholder engagement at Accra International Airport.",
        "done": false,
        "active": false,
        "date": "Pending"
      },
      {
        "step": 4,
        "title": "Resolution & Official Action",
        "desc": "Formal resolution notice issued by CUBAG Executive Committee.",
        "done": false,
        "active": false,
        "date": "Pending"
      }
    ]
  }
}
```

---

## 4. Integration Code Examples

### 4.1 JavaScript / TypeScript (Next.js / Frontend `fetch`)

```typescript
// services/cubagApi.ts
const BASE_URL = 'https://cubag-api-server.fly.dev/api/v1/public';

export interface PortalSummary {
  stats: {
    active_members: number;
    licensed_brokers: number;
    operating_ports: number;
    cti_courses: number;
  };
  exchange_rates: {
    usd_ghs: number;
    eur_ghs: number;
    gbp_ghs: number;
    cny_ghs: number;
    source: string;
    effective_date: string;
  };
  latest_news: Array<{
    id: number;
    title: string;
    summary: string;
    image_url: string;
    published_at: string;
  }>;
  bulletins: Array<{
    id: number;
    port_name: string;
    code: string;
    status: string;
    notice: string;
    status_color: string;
  }>;
  cti_courses: Array<{
    id: number;
    title: string;
    start_date: string;
    duration: string;
    fee: number;
    cohort_status: string;
  }>;
}

// 1. Fetch Consolidated Homepage
export async function getPortalSummary(): Promise<PortalSummary> {
  const res = await fetch(`${BASE_URL}/portal-summary`, {
    next: { revalidate: 60 } // Next.js ISR cache
  });
  if (!res.ok) throw new Error(`Portal summary error: ${res.status}`);
  return res.json();
}

// 2. Verify Member
export async function verifyMember(query: string) {
  const res = await fetch(`${BASE_URL}/verify-member?query=${encodeURIComponent(query)}`);
  return res.json();
}

// 3. Track Grievance
export async function trackComplaint(complaintId: string, token: string) {
  const res = await fetch(`${BASE_URL}/complaints/track/${encodeURIComponent(complaintId)}?token=${encodeURIComponent(token)}`);
  if (res.status === 401 || res.status === 404) {
    throw new Error('Invalid ticket ID or tracking token');
  }
  return res.json();
}
```

---

### 4.2 PHP / WordPress (`wp_remote_get`)

```php
<?php
/**
 * CUBAG Public API Client for WordPress
 */
class CUBAG_API_Client {
    private const BASE_URL = 'https://cubag-api-server.fly.dev/api/v1/public';

    /**
     * Retrieve composite homepage data with 60-second WordPress transient cache
     */
    public static function get_portal_summary() {
        $transient_key = 'cubag_portal_summary_data';
        $cached = get_transient($transient_key);
        if ($cached !== false) {
            return $cached;
        }

        $response = wp_remote_get(self::BASE_URL . '/portal-summary', [
            'timeout' => 8,
            'headers' => ['Accept' => 'application/json']
        ]);

        if (is_wp_error($response)) {
            return null;
        }

        $body = json_decode(wp_remote_retrieve_body($response), true);
        if (!empty($body['success'])) {
            set_transient($transient_key, $body, 60);
        }
        return $body;
    }

    /**
     * Verify Member Credentials
     */
    public static function verify_member($query) {
        $url = add_query_arg(['query' => sanitize_text_field($query)], self::BASE_URL . '/verify-member');
        $response = wp_remote_get($url, ['timeout' => 6]);
        if (is_wp_error($response)) return ['verified' => false, 'message' => 'Network error'];
        return json_decode(wp_remote_retrieve_body($response), true);
    }

    /**
     * Submit Trade Grievance with Honeypot Validation
     */
    public static function submit_complaint($payload) {
        $response = wp_remote_post(self::BASE_URL . '/complaints', [
            'timeout' => 10,
            'headers' => ['Content-Type' => 'application/json', 'Accept' => 'application/json'],
            'body'    => wp_json_encode($payload),
        ]);
        if (is_wp_error($response)) return ['success' => false, 'message' => 'Submission failed'];
        return json_decode(wp_remote_retrieve_body($response), true);
    }
}
```

---

### 4.3 cURL Command Reference

```bash
# 1. Consolidated Homepage (Returns X-Cache HIT/MISS)
curl -i https://cubag-api-server.fly.dev/api/v1/public/portal-summary

# 2. Member Verification
curl -s "https://cubag-api-server.fly.dev/api/v1/public/verify-member?query=CUBAG-2026-0008" | jq .

# 3. Cryptographic Receipt Verification
curl -s "https://cubag-api-server.fly.dev/api/v1/public/verify-receipt?token=943d21ee5518af43ba4a9fa039b173ef" | jq .

# 4. Grievance Tracking (Requires Secret Token)
curl -s "https://cubag-api-server.fly.dev/api/v1/public/complaints/track/CMP-2026-80069?token=de64c421cadcb0cab55346be70171c1a" | jq .
```

---

## 5. Support & Handover Contacts

For inquiries or custom integration support:
- **CUBAG Technical Secretariat:** `eaap2026@eventslabs.org`
- **Interactive Swagger UI:** [`https://cubag-api-server.fly.dev/api/v1/public/docs`](https://cubag-api-server.fly.dev/api/v1/public/docs)
- **Live Server Status:** [`https://cubag-api-server.fly.dev/health`](https://cubag-api-server.fly.dev/health)

