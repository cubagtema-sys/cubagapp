# CUBAG Public REST API — Endpoints, Fields & Call Specification

> **Base URL:** `https://cubag-api-server.fly.dev/api/v1/public`  
> **Interactive Swagger UI:** [https://cubag-api-server.fly.dev/api/v1/public/docs](https://cubag-api-server.fly.dev/api/v1/public/docs)  
> **Authentication:** None required (Zero-Auth public routes)  
> **CORS:** Enabled (`*`)

---

## Quick Overview: Parameterless vs Parameterized Endpoints

| Endpoint Category | Endpoints | Input Parameters | How to Call |
|---|---|---|---|
| **Direct Read (Zero Input)** | `/portal-summary`<br>`/stats`<br>`/news`<br>`/bulletins`<br>`/events`<br>`/courses`<br>`/ports`<br>`/gallery`<br>`/surveys` | **None** | Simple `GET` request. In Swagger, just click **Execute**. |
| **Lookup / Verification** | `/verify-member`<br>`/verify-receipt` | Query string params (`?query=...`, `?token=...`) | `GET` with URL parameters. |
| **Grievance Submission** | `/complaints` | JSON Request Body | `POST` with JSON payload. |
| **Grievance Tracking** | `/complaints/track/{id}` | Path param `{id}` + Query param `?token=...` | `GET` with ticket ID and secret token. |

---

## 1. Direct Read Endpoints (No Parameters Required)

### 1.1 Consolidated Homepage State
* **Method:** `GET`
* **URL:** `https://cubag-api-server.fly.dev/api/v1/public/portal-summary`
* **Parameters:** **None** (Click **Execute** directly)
* **Caching:** 60 seconds (`Cache-Control: public, max-age=60`, returns `X-Cache: HIT|MISS`)

#### Call Example
```bash
curl -s "https://cubag-api-server.fly.dev/api/v1/public/portal-summary"
```

```javascript
const res = await fetch("https://cubag-api-server.fly.dev/api/v1/public/portal-summary");
const data = await res.json();
```

#### Response Fields Breakdown

| Field | Type | Description |
|---|---|---|
| `success` | `boolean` | `true` if request succeeded |
| `stats.active_members` | `integer` | Count of registered active members |
| `stats.licensed_brokers` | `integer` | Count of licensed customs house agents |
| `stats.operating_ports` | `integer` | Count of operational ports/terminals |
| `stats.cti_courses` | `integer` | Count of active CTI training courses |
| `exchange_rates.usd_ghs` | `number` | USD to GHS exchange rate |
| `exchange_rates.eur_ghs` | `number` | EUR to GHS exchange rate |
| `exchange_rates.gbp_ghs` | `number` | GBP to GHS exchange rate |
| `exchange_rates.cny_ghs` | `number` | CNY to GHS exchange rate |
| `exchange_rates.source` | `string` | Data source (`Bank of Ghana Indicative Rates`) |
| `exchange_rates.effective_date` | `string` | ISO timestamp of exchange rate update |
| `latest_news[]` | `array` | List of press releases and news items |
| `latest_news[].id` | `integer` | News article identifier |
| `latest_news[].title` | `string` | Article title |
| `latest_news[].summary` | `string` | Short preview excerpt |
| `latest_news[].image_url` | `string` | URL to hero banner image |
| `latest_news[].source` | `string` | Publishing agency / source |
| `latest_news[].published_at` | `string` | ISO publication date |
| `bulletins[]` | `array` | Live operational notices per port/terminal |
| `bulletins[].id` | `integer` | Bulletin identifier |
| `bulletins[].port_name` | `string` | e.g. `Tema Port Terminal`, `Takoradi Port` |
| `bulletins[].code` | `string` | 3-letter port code (`TMP`, `TKD`, `KIA`) |
| `bulletins[].status` | `string` | Operational state (`Operational`, `Normal`, `Delay`) |
| `bulletins[].notice` | `string` | Current operational circular/guidance |
| `bulletins[].status_color` | `string` | Hex color code for UI badge (e.g. `#2E7D32`) |
| `upcoming_events[]` | `array` | Scheduled seminars and industry workshops |
| `upcoming_events[].id` | `integer` | Event identifier |
| `upcoming_events[].title` | `string` | Event title |
| `upcoming_events[].description` | `string` | Details of the event |
| `upcoming_events[].date` | `string` | Date (`YYYY-MM-DD`) |
| `upcoming_events[].time` | `string` | Event start time (`09:00 AM`) |
| `upcoming_events[].location` | `string` | Physical venue |
| `upcoming_events[].capacity` | `integer` | Attendee seat capacity |
| `cti_courses[]` | `array` | Customs Technical Institute courses |
| `cti_courses[].id` | `integer` | Course identifier |
| `cti_courses[].title` | `string` | Course title |
| `cti_courses[].start_date` | `string` | Cohort start date string |
| `cti_courses[].duration` | `string` | e.g. `4 Weeks` |
| `cti_courses[].mode` | `string` | Delivery mode (`Hybrid`, `In-Person`, `Online`) |
| `cti_courses[].fee` | `number` | Tuition fee amount |
| `cti_courses[].currency` | `string` | Fee currency (`GHS`) |
| `cti_courses[].cohort_status` | `string` | Enrollment status (`Enrollment Open`) |
| `cti_courses[].accredited` | `boolean` | Official accreditation status |
| `ports[]` | `array` | List of customs ports of entry |
| `ports[].id` | `integer` | Port identifier |
| `ports[].name` | `string` | Full port name |
| `ports[].code` | `string` | Official code (`TMA`, `TKD`, `ACC`, `AFL`, etc.) |
| `timestamp` | `string` | ISO timestamp of payload assembly |

---

### 1.2 Other Individual Direct Read Endpoints
The following endpoints also take **zero parameters**:

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/stats` | High-level numeric metrics (`active_members`, `licensed_brokers`, `operating_ports`, `cti_courses`) |
| `GET` | `/news` | Full list of published public news and circulars |
| `GET` | `/bulletins` | Live port circulars and operational notices |
| `GET` | `/events` | All upcoming CUBAG events and summits |
| `GET` | `/courses` | All Customs Technical Institute (CTI) training courses |
| `GET` | `/ports` | All registered Ghanaian ports, airports, and border posts |
| `GET` | `/gallery` | Public photo gallery from official events |
| `GET` | `/surveys` | Active public member polls and stakeholder surveys |

---

## 2. Lookup & Verification Endpoints (Query Parameters)

### 2.1 Verify Member / Broker Standing
Allows shippers, importers, and authorities to verify if a customs brokerage firm is officially registered and in Good Standing.

* **Method:** `GET`
* **URL:** `https://cubag-api-server.fly.dev/api/v1/public/verify-member`

#### Request Parameters (Query String)

| Parameter | Type | Required | Description | Example |
|---|---|---|---|---|
| `query` | `string` | **Yes** (min 3 chars) | Membership ID, License number, or Company Name | `CUBAG-2026-0008` or `Godfred Shipping` |

#### Call Example
```bash
curl -s "https://cubag-api-server.fly.dev/api/v1/public/verify-member?query=CUBAG-2026-0008"
```

```javascript
const query = encodeURIComponent("CUBAG-2026-0008");
const res = await fetch(`https://cubag-api-server.fly.dev/api/v1/public/verify-member?query=${query}`);
const data = await res.json();
```

#### Response Fields (When Found - HTTP 200)

| Field | Type | Description |
|---|---|---|
| `verified` | `boolean` | `true` if member exists and matches |
| `standing_status` | `string` | `Good Standing`, `Probationary`, or `Suspended` |
| `good_standing` | `boolean` | `true` if fully cleared to practice |
| `company_name` | `string` | Registered corporate name |
| `membership_number` | `string` | Official CUBAG member code (`CUBAG-2026-XXXX`) |
| `license_number` | `string` | Customs Broker License code |
| `member_category` | `string` | `Corporate Member`, `Individual`, etc. |
| `primary_port` | `string` | Primary operational port (e.g. `Tema Port`) |
| `valid_until` | `string` | Expiration date of current practicing license |
| `verified_at` | `string` | Human-readable verification timestamp |

#### Response (When Not Found - HTTP 200)
```json
{
  "verified": false,
  "message": "No verified CUBAG member found matching those credentials. Please check the membership or license number."
}
```

---

### 2.2 Verify Payment Receipt
Validates QR codes on invoices, practicing certificates, or dues receipts.

* **Method:** `GET`
* **URL:** `https://cubag-api-server.fly.dev/api/v1/public/verify-receipt`

#### Request Parameters (Query String)

| Parameter | Type | Required | Description | Example |
|---|---|---|---|---|
| `token` | `string` | **Yes** (min 16 chars) | Cryptographic verification hash (from receipt QR code) | `943d21ee5518af43ba4a9fa039b173ef` |
| `amount` | `number` | Optional | Optional check against expected invoice sum | `850.00` |

*(Note: Guessing sequential numbers like `?token=1` or `?token=TXN-0001` returns `HTTP 400 Bad Request` to prevent enumeration).*

#### Call Example
```bash
curl -s "https://cubag-api-server.fly.dev/api/v1/public/verify-receipt?token=943d21ee5518af43ba4a9fa039b173ef"
```

#### Response Fields (HTTP 200)

| Field | Type | Description |
|---|---|---|
| `verified` | `boolean` | `true` if legitimate and recorded |
| `verification_token` | `string` | Echoed cryptographic token |
| `status` | `string` | `completed`, `paid`, or `pending` |
| `amount` | `number` | Paid transaction amount |
| `currency` | `string` | Currency code (`GHS`) |
| `description` | `string` | Payment purpose (e.g. `Annual Practicing License Renewal`) |
| `issued_at` | `string` | Invoice issue date/time |
| `paid_at` | `string` | Settlement date/time |
| `issuing_authority` | `string` | `Customs Brokers Association Ghana (CUBAG)` |
| `verified_at` | `string` | Current timestamp of lookup |

---

## 3. Grievance Form & Tracking Endpoints

### 3.1 Lodge a Complaint / Port Grievance
Allows importers, freight forwarders, or the public to submit trade disputes, demurrage issues, or port complaints.

* **Method:** `POST`
* **URL:** `https://cubag-api-server.fly.dev/api/v1/public/complaints`
* **Headers:** `Content-Type: application/json`

#### Request Body Fields (JSON)

| Field | Type | Required | Description | Example |
|---|---|---|---|---|
| `name` | `string` | **Yes** | Full name of the complainant | `"Kwame Asante"` |
| `email` | `string` | **Yes** | Email address for status updates | `"kwame.asante@example.com"` |
| `phone` | `string` | Optional | Contact phone / WhatsApp number | `"+233244000111"` |
| `category` | `string` | **Yes** | Grievance classification | `"Port Demurrage Dispute"`, `"ICUMS Technical"`, `"Broker Misconduct"` |
| `port` | `string` | Optional | Affected port / terminal | `"Tema Port"`, `"Takoradi Port"` |
| `target_entity` | `string` | Optional | Company or agency involved | `"Shipping Line Agency"` |
| `subject` | `string` | **Yes** | Short summary title | `"Excess Detention Charge Assessment"` |
| `description` | `string` | **Yes** | Full details of the dispute | `"Container released within free days but detention invoices billed at gate out."` |
| `hp_field` | `string` | **Yes** (leave empty) | **Anti-Spam Honeypot:** Form must include this hidden via CSS. Human users leave it empty. If populated by a bot, the submission is rejected. | `""` |

#### Call Example
```bash
curl -X POST https://cubag-api-server.fly.dev/api/v1/public/complaints \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Kwame Asante",
    "email": "kwame.asante@example.com",
    "phone": "+233244000111",
    "category": "Port Demurrage Dispute",
    "port": "Tema Port",
    "subject": "Excess Detention Charge Assessment",
    "description": "Detention billed incorrectly.",
    "hp_field": ""
  }'
```

#### Response Fields (HTTP 201 Created)

| Field | Type | Description |
|---|---|---|
| `success` | `boolean` | `true` |
| `message` | `string` | Confirmation message instructing user to save their token |
| `complaint_id` | `string` | Official tracking ticket ID (e.g. `CMP-2026-80069`) |
| `tracking_token` | `string` | **Crucial:** 128-bit private token required to check status later |
| `data.complaint_id` | `string` | Echoed complaint ID |
| `data.status` | `string` | Initial status (e.g. `Received`) |
| `data.created_at` | `string` | ISO timestamp of submission |

---

### 3.2 Track Complaint Status Timeline
Retrieves the 4-stage resolution timeline for a submitted grievance.

* **Method:** `GET`
* **URL:** `https://cubag-api-server.fly.dev/api/v1/public/complaints/track/{complaint_id}`

#### Request Parameters

| Parameter | Location | Type | Required | Description | Example |
|---|---|---|---|---|---|
| `complaint_id` | Path | `string` | **Yes** | Ticket ID from submission | `CMP-2026-80069` |
| `token` | Query or Header | `string` | **Yes** | 128-bit secret tracking token | `de64c421cadcb0cab55346be70171c1a` |

*(Pass `token` either in the query string: `?token=...` or in the header: `X-Tracking-Token: ...`)*

#### Call Example
```bash
curl -s "https://cubag-api-server.fly.dev/api/v1/public/complaints/track/CMP-2026-80069?token=de64c421cadcb0cab55346be70171c1a"
```

#### Response Fields (HTTP 200)

| Field | Type | Description |
|---|---|---|
| `success` | `boolean` | `true` |
| `data.complaint_id` | `string` | Ticket ID |
| `data.category` | `string` | Complaint category |
| `data.port` | `string` | Affected port |
| `data.status` | `string` | Current progress status (`Received`, `Under Review`, `Investigating`, `Resolved`) |
| `data.timeline[]` | `array` | 4-step Secretariat resolution pipeline |
| `data.timeline[].step` | `integer` | Step number (`1` to `4`) |
| `data.timeline[].title` | `string` | Stage name (e.g. `Secretariat Review`, `Port Investigation`) |
| `data.timeline[].desc` | `string` | Description of action taking place in this step |
| `data.timeline[].done` | `boolean` | `true` if this stage is completed |
| `data.timeline[].active` | `boolean` | `true` if this stage is currently in progress |
| `data.timeline[].date` | `string` | Completion timestamp or `Pending` |

---

## 4. HTTP Status & Error Codes

| Status Code | Reason | What to Do |
|---|---|---|
| **`200 OK`** | Request succeeded | Render the returned data. |
| **`201 Created`** | Complaint submitted successfully | Save and display the returned `complaint_id` and `tracking_token`. |
| **`400 Bad Request`** | Missing required parameter or invalid token format | Check required fields and minimum lengths. |
| **`401 Unauthorized`** | Missing or incorrect tracking token on `/track/{id}` | Provide the secret token generated during complaint submission. |
| **`404 Not Found`** | Resource or ticket ID does not exist | Verify the ID / query. |
| **`429 Too Many Requests`** | Rate limit exceeded | Respect `Retry-After` header before retrying. |
| **`500 Internal Error`** | Server-side exception | Contact CUBAG Technical Secretariat (`[EMAIL_ADDRESS]`). |
