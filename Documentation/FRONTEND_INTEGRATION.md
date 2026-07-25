# MR.CREAMS Frontend Integration Documentation

Last updated: 2026-07-25
Backend version: 1.0.0
Backend source: `server.js`, `routes/auth.js`, `routes/*`, `middleware/auth.js`, `middleware/security.js`

---

## 1. Quick Start

### 1.1 Environment Setup

Default backend URL for local development is **`http://localhost:5001`**.

Create a frontend env file (`.env`, `.env.local`, etc.) with:

```
# React (Create React App / Vite)
REACT_APP_API_URL=http://localhost:5001
VITE_API_URL=http://localhost:5001

# If your auth library supports refresh tokens explicitly
REACT_APP_REFRESH_URL=http://localhost:5001/api/auth/refresh
```

If you run the frontend on a **port other than 3000, 3001, or 5173**, add it to the backend's `ALLOWED_ORIGINS` in `.env` and restart the backend.

### 1.2 Base URLs

| Environment | Base URL                          | Frontend default   |
|-------------|-----------------------------------|--------------------|
| Local dev   | `http://localhost:5001`           | `http://localhost:3000` |
| Production  | Set `FRONTEND_URL` + `ALLOWED_ORIGINS` in backend `.env` | Your deployed domain |

Un-authenticated health and API discovery endpoints:

- `GET /health` — overall backend + database status
- `GET /status` — runtime environment, CORS whitelist, DB connectivity
- `GET /api`    — endpoint index

### 1.3 Authentication Flow (Summary)

1. Register with `POST /api/auth/register` → `201 Created`. User must verify email (token sent via email).
2. Login with `POST /api/auth/login` → receive `{ token, refreshToken, expiresAt, user }`.
3. Store **access token** and **refresh token** securely (`HttpOnly` cookies if possible, else `localStorage` with CSRF awareness).
4. For every protected request send header: `Authorization: Bearer <token>`.
5. On `401` with code `TOKEN_EXPIRED`, call `POST /api/auth/refresh` with `{ refreshToken }` → new tokens.
6. Call `POST /api/auth/logout` or `/logout-all` to revoke tokens server-side.

---

## 2. Transport / CORS

### 2.1 CORS Policy

The backend uses a **dynamic whitelist** in [server.js](file:///Users/Cappie/Documents/MRCREAMS-Api/MRCREAMS-Api/server.js#L49-L68).

- **In `NODE_ENV=development`**: any origin is accepted (`Access-Control-Allow-Origin: *` is NOT used; it mirrors the request origin). Credentials mode is supported.
- **In `NODE_ENV=production`**: only origins listed in `ALLOWED_ORIGINS` are accepted. Mismatched origins return an error.

### 2.2 Fetch / Axios Setup

Credentials (`cookies` / `Authorization`) require `credentials: 'include'` (fetch) or `withCredentials: true` (axios) if your auth flow uses cookies. JWT in the Authorization header does not require credentials mode, but it's harmless to enable it.

**Axios example:**
```javascript
import axios from 'axios';

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || process.env.REACT_APP_API_URL || 'http://localhost:5001',
  timeout: 30_000,
  withCredentials: true, // optional for JWT-header-only flow
  headers: {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  },
});

// Attach bearer token to every outgoing request
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('mrcreams.token');
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

// Auto-refresh on 401
let refreshPromise = null;
api.interceptors.response.use(
  (r) => r,
  async (err) => {
    const original = err.config;
    if (!err.response) throw err;

    const isAuth401 = err.response.status === 401 &&
      err.response.data?.code !== 'INVALID_CREDENTIALS' &&
      err.response.data?.code !== 'MISSING_TOKEN';

    if (isAuth401 && !original._retry) {
      original._retry = true;
      if (!refreshPromise) {
        const rt = localStorage.getItem('mrcreams.refreshToken');
        refreshPromise = api.post('/api/auth/refresh', { refreshToken: rt })
          .then(({ data }) => {
            localStorage.setItem('mrcreams.token', data.token);
            localStorage.setItem('mrcreams.refreshToken', data.refreshToken);
            return data.token;
          })
          .finally(() => { refreshPromise = null; });
      }
      try {
        const newToken = await refreshPromise;
        original.headers.Authorization = `Bearer ${newToken}`;
        return api(original);
      } catch (refreshErr) {
        localStorage.removeItem('mrcreams.token');
        localStorage.removeItem('mrcreams.refreshToken');
        window.location.href = '/login?reason=session-expired';
        throw refreshErr;
      }
    }
    return Promise.reject(err);
  }
);

export default api;
```

**`fetch` example:**
```javascript
const BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:5001';

export async function mrcreamsFetch(path, opts = {}) {
  const headers = {
    'Accept': 'application/json',
    ...(opts.body && !(opts.body instanceof FormData) && { 'Content-Type': 'application/json' }),
    ...opts.headers,
  };
  const token = localStorage.getItem('mrcreams.token');
  if (token) headers.Authorization = `Bearer ${token}`;

  let res = await fetch(BASE_URL + path, {
    ...opts,
    headers,
    credentials: 'include',
    body: opts.body instanceof FormData ? opts.body : (opts.body ? JSON.stringify(opts.body) : undefined),
  });

  if (res.status === 401) {
    const data = await res.clone().json().catch(() => ({}));
    if (data.code && data.code !== 'INVALID_CREDENTIALS' && data.code !== 'MISSING_TOKEN') {
      const rt = localStorage.getItem('mrcreams.refreshToken');
      const refresh = await fetch(BASE_URL + '/api/auth/refresh', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refreshToken: rt }),
      });
      if (refresh.ok) {
        const r = await refresh.json();
        localStorage.setItem('mrcreams.token', r.token);
        localStorage.setItem('mrcreams.refreshToken', r.refreshToken);
        headers.Authorization = `Bearer ${r.token}`;
        res = await fetch(BASE_URL + path, { ...opts, headers, credentials: 'include', body: opts.body instanceof FormData ? opts.body : (opts.body ? JSON.stringify(opts.body) : undefined) });
      } else {
        localStorage.removeItem('mrcreams.token');
        localStorage.removeItem('mrcreams.refreshToken');
        window.location.href = '/login?reason=session-expired';
      }
    }
  }
  return res;
}
```

### 2.3 Rate Limiting

Backend applies two global limiters (see [server.js](file:///Users/Cappie/Documents/MRCREAMS-Api/MRCREAMS-Api/server.js#L102-L117)).

| Scope        | Window   | Limit (dev) | Limit (prod) | Response code | Response body                          |
|--------------|----------|-------------|--------------|---------------|----------------------------------------|
| All `/api/*` | 15 min   | 5000/IP     | 100/IP       | 429           | `{ error, code: "RATE_LIMIT_EXCEEDED" }` |
| `/api/auth/*` (login/register/refresh) | 60 s | 200/IP | 20/IP | 429 | `{ error, code: "AUTH_RATE_LIMIT_EXCEEDED" }` |

In addition, `requestFrequencyLimit` enforces a configurable per-minute cap from `RATE_LIMIT_WINDOW` / `RATE_LIMIT_MAX` env vars (default: 60 000 ms, 100 requests) with `FREQUENCY_LIMIT_EXCEEDED` code and a `retryAfter` (seconds) integer.

Frontend recommendation: respect the `Retry-After` / `RateLimit-Reset` standard headers, and add a UI throttle on submit buttons for login/register to avoid hitting the auth limiter.

---

## 3. Authentication Endpoints

All endpoints are under `/api/auth` mounted from [routes/auth.js](file:///Users/Cappie/Documents/MRCREAMS-Api/MRCREAMS-Api/routes/auth.js).

### 3.1 Register

`POST /api/auth/register` — **Public**

#### Request body

```json
{
  "email": "jordan@example.com",
  "password": "VerySecure1!+",
  "name": "Jordan Smith",
  "userType": "individual",
  "metadata": { "ageRange": "25-34", "relationshipLengthMonths": 18 },
  "organizationCode": "MRCREAMS-9F3A"
}
```

| Field              | Required | Notes                                                     |
|--------------------|----------|-----------------------------------------------------------|
| `email`            | yes      | unique, case-insensitive                                  |
| `password`         | yes      | min 8 chars, upper/lower/number/symbol — see §7.2         |
| `name`             | yes      | display name, 1–100 chars                                 |
| `userType`         | yes      | one of: `individual`, `couple`, `therapist`, `support`, `executive`, `admin`, `platform_admin`. In a self-serve frontend, only allow `individual`/`couple`/`therapist`. Admin roles must be created via `scripts/createSuperAdmin.js` or existing platform-admin promotion endpoints. |
| `metadata`         | no       | free-form JSON stored in `user_metadata`                  |
| `organizationCode` | no       | 6+ char code from the `organizations.code` column. Joins the user to that org on creation. |

⚠️ **Breaking note**: the field is `userType` (camelCase), not `user_type`. Sending `user_type` triggers `MISSING_FIELDS`.

#### Response — `201 Created`

```json
{
  "message": "Registration successful. Please check your email to verify your account.",
  "user": {
    "id": 42,
    "email": "jordan@example.com",
    "name": "Jordan Smith",
    "userType": "individual",
    "organizationId": 3,
    "onboardingCompleted": false,
    "emailVerified": false
  }
}
```

Register does **not** return tokens; the user must login. Two emails are dispatched: verification + welcome (if SMTP is configured; if no SMTP env vars, email send is a no-op but the `email_verification_token` is still stored — platform admins can verify users manually).

#### Common error codes

| HTTP | Code                  | Cause                                                      |
|------|-----------------------|------------------------------------------------------------|
| 400  | `MISSING_FIELDS`      | `email/password/name/userType` missing or `user_type` used |
| 400  | `INVALID_EMAIL`       | email format fails RFC 5322 check                          |
| 400  | `WEAK_PASSWORD`       | `details: string[]` contains each failure rule             |
| 400  | `USER_EXISTS`         | `email` already taken (case-insensitive)                   |
| 500  | `REGISTRATION_ERROR`  | unhandled DB/transaction error                             |

### 3.2 Login

`POST /api/auth/login` — **Public**

Request:
```json
{
  "email": "jordan@example.com",
  "password": "VerySecure1!+"
}
```

Response — `200 OK`:
```json
{
  "message": "Login successful",
  "user": {
    "id": 42,
    "email": "jordan@example.com",
    "name": "Jordan Smith",
    "userType": "individual",
    "organizationId": 3,
    "organizationName": "Acme Wellness",
    "organizationCode": "MRCREAMS-9F3A",
    "onboardingCompleted": false,
    "emailVerified": true
  },
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expiresAt": "2026-07-26T16:19:45.123Z"
}
```

The `user` object is the **source of truth for role checks** in the frontend. It is **NOT** re-fetched from JWT automatically. If you need fresh user data (e.g., after profile update), call the `/api/auth/me` endpoint and re-assign the cached user.

Failed login returns `401 { error: "Invalid credentials", code: "INVALID_CREDENTIALS" }` — same message for unknown email or bad password to prevent enumeration.

### 3.3 Professional Login

`POST /api/auth/professional-login` — **Public**

Same as `/login` plus optional `organizationCode` and `role` for org-scoped dashboards. Returns the same shape as login with `success: true/false` wrapper.

### 3.4 Token Refresh

`POST /api/auth/refresh` — **Public** (requires valid refresh token body)

Request:
```json
{ "refreshToken": "<refresh JWT from login response>" }
```

Response — `200`: same shape as login (`token`, `refreshToken`, `expiresAt`, `user`). Do not re-send the user to the backend with every refresh; keep the existing user object, or update it only if `user.userType`/`organizationId` changed.

Errors:
- 400 `MISSING_REFRESH_TOKEN`
- 401 `INVALID_REFRESH_TOKEN`
- 401 `REVOKED_REFRESH_TOKEN`  (if user logged out / changed password / session was revoked by admin)

When you see any of these, the frontend should:
1. Clear token cache
2. Show "Your session has expired"
3. Redirect to `/login?reason=session-expired`

### 3.5 Logout

`POST /api/auth/logout` — **Protected**

Revokes the current access token's session. Body optional (the backend reads the bearer token from the header). Response: `200 { message: "Logout successful" }`.

`POST /api/auth/logout-all` — **Protected** — revokes every session for the current user (use this for the "Log out of all devices" action).

### 3.6 Email + Password Recovery Flows

| Method | Route                                         | Purpose                                                     |
|--------|-----------------------------------------------|-------------------------------------------------------------|
| POST   | `/api/auth/resend-verification`               | Body `{ email }`. Re-sends verification link.               |
| POST   | `/api/auth/verify-email`                      | Body `{ token }` — marks `email_verified = true`.           |
| POST   | `/api/auth/forgot-password`                   | Body `{ email }` — dispatches password reset email.        |
| POST   | `/api/auth/reset-password`                    | Body `{ token, password }` — sets new password.            |

### 3.7 Current User

`GET /api/auth/me` — **Protected**

Returns the same `user` shape as login, freshly read from the database. Use it:
- On app bootstrap, if a non-expired access token exists in storage, to rebuild the in-memory user object
- After any profile/settings mutation, to refresh role and onboarding state

`PATCH /api/auth/me` — **Protected**

Accepts `{ name, timezone, language, preferences (JSON blob) }`. Returns updated user.

### 3.8 Onboarding + Email Guards

Many actions are gated by two backend middleware flags (see [middleware/auth.js](file:///Users/Cappie/Documents/MRCREAMS-Api/MRCREAMS-Api/middleware/auth.js)):

- `requireEmailVerification` — returns `403 { code: "EMAIL_NOT_VERIFIED" }`
- `requireOnboardingCompletion` — returns `403 { code: "ONBOARDING_INCOMPLETE" }`

Frontend flow recommendation:
- After login, check `user.emailVerified === false` → block app and show "Check your inbox" UI with a resend button
- After login, check `user.onboardingCompleted === false` → route to `/onboarding`. On onboarding completion, call the onboarding finish endpoint; do **not** depend purely on frontend state — reload user from `/api/auth/me` once it returns `200`.

---

## 4. Role-Based Access Control (RBAC)

### 4.1 Roles

Stored on each user as `user.userType` (DB column `user_type`):

| Role            | Purpose                                                      |
|-----------------|--------------------------------------------------------------|
| `super_admin`   | unrestricted platform owner, can manage system configuration, other admins, backups |
| `platform_admin`| cross-org admin, can run `/api/platform/*` dashboards, audit logs, user bulk actions |
| `admin`         | organization-scoped admin, manages own org's users, content, reports |
| `it_admin`      | org IT staff — security, integration, API keys scoped to org |
| `support`       | customer support agent — tickets, user lookups, escalation   |
| `therapist`     | licensed/certified mental health professional — clients, sessions, notes |
| `executive`     | org executive — read-only dashboards + reports               |
| `individual`    | end user (couple member) — conflicts, emotions, own sessions |
| `couple`        | end user (couple account placeholder, used like `individual`) |

### 4.2 Convenience booleans

Every protected request populates these on the server side (mirror them in the frontend for UI gating):

```
isAdmin:         userType in ['super_admin','platform_admin','admin','it_admin']
isSuperAdmin:    userType === 'super_admin'
isPlatformAdmin: userType in ['super_admin','platform_admin']
isSupport:       userType in ['super_admin','platform_admin','admin','it_admin','support']
isTherapist:     userType === 'therapist'
```

### 4.3 Frontend Permission Helpers

Mirror this logic in your auth store:

```typescript
export type MRCRole = 'super_admin'|'platform_admin'|'admin'|'it_admin'|'support'|'therapist'|'executive'|'individual'|'couple';

export interface MRCUser {
  id: number; email: string; name: string;
  userType: MRCRole;
  organizationId?: number | null;
  organizationName?: string | null;
  organizationCode?: string | null;
  onboardingCompleted: boolean;
  emailVerified: boolean;
}

export function withRoleFlags(u: MRCUser | null) {
  if (!u) return { user: null, isAdmin:false, isSuperAdmin:false, isPlatformAdmin:false, isSupport:false, isTherapist:false };
  const adminRoles = new Set(['super_admin','platform_admin','admin','it_admin']);
  const supportRoles = new Set(['super_admin','platform_admin','admin','it_admin','support']);
  return {
    user: u,
    isAdmin: adminRoles.has(u.userType),
    isSuperAdmin: u.userType === 'super_admin',
    isPlatformAdmin: u.userType === 'super_admin' || u.userType === 'platform_admin',
    isSupport: supportRoles.has(u.userType),
    isTherapist: u.userType === 'therapist',
  };
}
```

### 4.4 Route Guards (React Router v6 example)

```tsx
import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from './authStore';

export function RequireAuth({ children }: { children: React.ReactNode }) {
  const { user, isLoading } = useAuth();
  const location = useLocation();
  if (isLoading) return <p>Loading…</p>;
  if (!user) return <Navigate to="/login" replace state={{ from: location }} />;
  if (!user.emailVerified) return <Navigate to="/verify-email" replace />;
  if (!user.onboardingCompleted) return <Navigate to="/onboarding" replace />;
  return <>{children}</>;
}

export function RequireAdmin({ children }: { children: React.ReactNode }) {
  const { user, isLoading, isAdmin } = useAuth();
  if (isLoading) return <p>Loading…</p>;
  if (!user) return <Navigate to="/login" replace />;
  if (!isAdmin) return <Navigate to="/403" replace />;
  return <>{children}</>;
}
```

### 4.5 Ownership vs Admin Access

Resource endpoints like `/api/conflicts/:id` follow a rule encoded in [server.js](file:///Users/Cappie/Documents/MRCREAMS-Api/MRCREAMS-Api/server.js#L224-L362):

- **Admins** (`isAdmin === true`) can read/update/delete any row
- **Non-admins** (`individual`/`couple`/`therapist`) can only read/update/delete rows whose `user_id` matches their `user.id`

The backend silently narrows non-admin selects by `user_id`. If a non-admin requests someone else's row, the response is `404`, not `403` — this prevents row enumeration.

Frontend consequence: **do not build deep-links** to `conflicts/:id` for non-admin users that were shared by another user. The viewer will hit 404 if they aren't the owner.

---

## 5. Conflict CRUD (Core Feature)

Mounted directly in [server.js](file:///Users/Cappie/Documents/MRCREAMS-Api/MRCREAMS-Api/server.js#L222-L417). **All endpoints require authentication.**

### Conflict object

```typescript
interface Conflict {
  id: number;
  user_id: number;
  date: string;          // ISO date string (YYYY-MM-DD)
  time: string;          // ISO time string (HH:MM:SS)
  conflict_reason: string;
  description: string | null;
  time_consumption: number;  // minutes, integer >= 0
  fight_degree: number;       // 1..10
  final_result: string | null;
  remark: string | null;
  partner_id: number | null;
  created_at: string;
  updated_at: string;
  user_name?: string;     // only on read responses
  user_email?: string;    // only on read responses
}
```

### Endpoints

| Method | URL                  | Scope                              |
|--------|----------------------|------------------------------------|
| GET    | `/api/conflicts`     | list (owner or admin)              |
| GET    | `/api/conflicts/:id` | get one (owner or admin)           |
| POST   | `/api/conflicts`     | create (owner = `req.user.id`)     |
| PUT    | `/api/conflicts/:id` | update (owner or admin)            |
| DELETE | `/api/conflicts/:id` | delete (owner or admin)            |

#### POST `/api/conflicts` — required fields
`date`, `time`, `conflict_reason`, `time_consumption`, `fight_degree`. Missing any → `400 MISSING_FIELDS`.

Sample payload:
```json
{
  "date": "2026-07-24",
  "time": "19:45:00",
  "conflict_reason": "Household chores",
  "description": "Disagreement about who cleans the kitchen, escalated into silence.",
  "time_consumption": 45,
  "fight_degree": 6,
  "final_result": "Compromised: schedule chart created",
  "remark": "Note to self — don't bring this up before bedtime.",
  "partner_id": 51
}
```
Response: `201 Created` with full conflict object.

#### PUT `/api/conflicts/:id`
Takes same fields (all overwritten on each call), returns `200` with updated row.

#### Error cases
- `401 MISSING_TOKEN` — no bearer header
- `401 TOKEN_EXPIRED` / `INVALID_TOKEN` etc. (standard JWT errors)
- `404` — ID does not exist **or** non-admin requesting another user's row (indistinguishable by design)
- `500` — DB constraint / connectivity

### Query filters / pagination (GET /api/conflicts)

Currently unfiltered server-side. Frontend recommendations:
- Paginate in-memory or add `?limit=50&offset=0` params with axios `params`
- Date range: filter by `date` column client-side, or add backend query params as needed

---

## 6. Analytics + Recommendations Endpoints

Mounted inline in `server.js` and also available via dedicated routers.

### 6.1 Aggregate analytics

`GET /api/analytics` — **Protected** (non-admins see only their own data; admins see global data)

Response shape:
```json
{
  "totalConflicts": 128,
  "conflictsByReason": [
    { "name": "Household chores", "value": 37 },
    { "name": "Money / finances", "value": 24 }
  ],
  "avgFightDegree": "5.2",
  "avgTimeConsumption": "34.6",
  "monthlyTrends": [
    { "month": "2026-04", "count": 11, "avg_degree": "4.9" },
    { "month": "2026-05", "count": 14, "avg_degree": "5.3" }
  ]
}
```

Full analytics suite also exposed via `GET /api/analytics/*` router and `GET /api/reports/*` router (see [routes/analyticsRoutes.js](file:///Users/Cappie/Documents/MRCREAMS-Api/MRCREAMS-Api/routes/analyticsRoutes.js) and [routes/reportingRoutes.js](file:///Users/Cappie/Documents/MRCREAMS-Api/MRCREAMS-Api/routes/reportingRoutes.js)), including CSV exports for admin users.

### 6.2 Recommendations (public-ish, no auth required)

`GET /api/recommendations` — returns heuristics about the system's recent data: `commonReasons[]`, `highIntensityConflicts[]`, `longConflicts[]`.

Use on the landing/dashboard page as a teaser of analytics; do **not** expose individual conflict `id`/`remark` to unauthenticated users via this endpoint if you later add sensitive fields.

---

## 7. Input Validation Reference

All request bodies pass through input sanitization middleware (`sanitizeInput`, `securityValidation`, `validatePayloadSize`) before reaching handlers.

### 7.1 Payload Size Limits

- Default max body size: **10 MB** (`MAX_REQUEST_SIZE`, env-overridable)
- `multipart/form-data` uploads: use routes that consume Busboy/Multer (emotion images, therapist credentials upload via `/api/therapists/*`).

### 7.2 Password Strength Rules

Enforced on register + password reset + password change by [services/authService.js](file:///Users/Cappie/Documents/MRCREAMS-Api/MRCREAMS-Api/services/authService.js) `validatePassword()`:
- Length ≥ 8
- Contains at least 1 uppercase letter (A–Z)
- Contains at least 1 lowercase letter (a–z)
- Contains at least 1 digit (0–9)
- Contains at least 1 non-alphanumeric character (`!@#$%^&*...`)
- Not in a built-in common-password list (blocked)

Frontend should mirror these rules in an `onChange` validator and show the failure reasons live from the `WEAK_PASSWORD.details` array if the backend rejects it.

---

## 8. Standard Error Format

Every backend error response (4xx/5xx) uses a consistent JSON envelope:

```json
{
  "error": "Human-readable message",
  "code": "SNAKE_CASE_MNEMONIC",
  "details": ["optional rule breakdowns"]
}
```

Common `code` values (use these instead of string-matching `error`):

| Code                      | HTTP | When                                                 |
|---------------------------|------|------------------------------------------------------|
| `MISSING_TOKEN`           | 401  | no `Authorization: Bearer …` header on protected route |
| `INVALID_TOKEN`           | 401  | token signature invalid / malformed                  |
| `TOKEN_EXPIRED`           | 401  | access token expired → try refresh                   |
| `REVOKED_TOKEN`           | 401  | session revoked server-side (logout / password change) |
| `MISSING_REFRESH_TOKEN`   | 400  | refresh body is empty                                |
| `INVALID_REFRESH_TOKEN`   | 401  | refresh JWT invalid                                  |
| `REVOKED_REFRESH_TOKEN`   | 401  | refresh session revoked                              |
| `INVALID_CREDENTIALS`     | 401  | login email/password wrong                           |
| `EMAIL_NOT_VERIFIED`      | 403  | endpoint requires verified email                     |
| `ONBOARDING_INCOMPLETE`   | 403  | endpoint requires onboarding completion              |
| `FORBIDDEN`               | 403  | role-based / ownership / org access denied           |
| `MISSING_FIELDS`          | 400  | required fields missing / wrong field case (e.g., `user_type`) |
| `INVALID_EMAIL`           | 400  | email format                                         |
| `WEAK_PASSWORD`           | 400  | password strength rules (`details[]` populated)      |
| `USER_EXISTS`             | 400  | duplicate registration email                         |
| `NOT_FOUND`               | 404  | unknown route / missing resource                     |
| `AUTH_RATE_LIMIT_EXCEEDED`| 429  | too many login attempts                              |
| `RATE_LIMIT_EXCEEDED`     | 429  | global API rate limit                                |
| `FREQUENCY_LIMIT_EXCEEDED`| 429  | short-window frequency cap (`retryAfter` seconds in response) |
| `REGISTRATION_ERROR`      | 500  | unhandled DB/transaction during register             |
| `LOGIN_ERROR`             | 500  | unhandled DB/transaction during login                |
| `INTERNAL_ERROR`          | 500  | catch-all for unknown errors                         |

In development (`NODE_ENV !== "production"`), 500 responses also include a `stack` property for debugging. Do NOT try to parse this in UI code.

---

## 9. Additional Route Prefixes

All mounted from `server.js`:

| Prefix                   | Source file                                                      | Main consumers                 |
|--------------------------|------------------------------------------------------------------|---------------------------------|
| `/api/auth`              | `routes/auth.js`                                                 | login/register/account         |
| `/api/v1/auth`           | `routes/authRoutes.js`                                           | legacy/mobile clients (v1 API) |
| `/api/admin` + `/api/v1/admin` | `routes/adminRoutes.js`                                   | org-admin users                |
| `/api/v1/support`        | `routes/supportTickets.js`                                       | support agents / ticket UI     |
| `/api/emotions`          | `routes/emotionAnalysis.js`                                      | emotion check-ins + AI analysis|
| `/api/therapists`        | `routes/therapistRoutes.js`                                      | therapist portal + client list |
| `/api/mobile`            | `routes/mobileRoutes.js`                                         | mobile apps                    |
| `/api/analytics`         | inline + `routes/analyticsRoutes.js`                             | dashboards                     |
| `/api/reports`           | `routes/reportingRoutes.js`                                      | downloadable reports           |
| `/api/public`            | `routes/publicAPIRoutes.js`                                      | anonymous public endpoints     |
| `/api/integrations`      | `routes/integrationRoutes.js`                                    | 3rd-party OAuth callback flows |
| `/api/hipaa`             | `routes/hipaaComplianceRoutes.js`                                | HIPAA audit/access controls    |
| `/api/gdpr`              | `routes/gdprComplianceRoutes.js`                                 | subject access + erasure       |
| `/api/security`          | `routes/securityRoutes.js`                                       | security events dashboard      |
| `/api/platform`          | `routes/platformRoutes.js`                                       | platform-admin super-set       |
| `/api/payments` + `/api` (stripe webhooks) | `routes/paymentRoutes.js`                     | billing + checkout             |
| `/metrics`               | `routes/metricsRoutes.js`                                        | Prometheus scraper only        |

For detailed request/response of each sub-route, read the matching source file — every handler is fully annotated with its expected body/params.

---

## 10. Testing Your Integration Locally

### 10.1 Shell smoke tests

Copy/paste into your terminal to validate the backend is alive and your API client code would receive the correct shapes:

```bash
# Backend already running on 5001
curl -s http://localhost:5001/health | python3 -m json.tool
curl -s http://localhost:5001/api    | python3 -m json.tool

# Register
REG=$(curl -s -X POST http://localhost:5001/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"frontend-demo@example.com","password":"VerySecure1!+","name":"Frontend Demo","userType":"individual"}')
echo "$REG" | python3 -m json.tool

# Login
LOGIN=$(curl -s -X POST http://localhost:5001/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"frontend-demo@example.com","password":"VerySecure1!+"}')
echo "$LOGIN" | python3 -m json.tool
TOKEN=$(echo "$LOGIN" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token",""))')

# Protected call (conflicts list)
curl -s http://localhost:5001/api/conflicts -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

### 10.2 Local Development Checklist

Before your first end-to-end run:

- [ ] Backend `.env` has `ALLOWED_ORIGINS` including your frontend origin
- [ ] PostgreSQL is running and schema initialized (`npm run setup:db` once)
- [ ] Frontend `REACT_APP_API_URL` / `VITE_API_URL` points to backend
- [ ] Register a user from the frontend and confirm you can login
- [ ] Confirm that visiting a protected route with no token redirects to login
- [ ] Confirm that deleting the token in DevTools and navigating triggers 401 → auto-refresh or logout

---

## 11. Troubleshooting

### "My requests fail CORS / preflight in the browser"

Checklist:
1. Your frontend's origin appears in `ALLOWED_ORIGINS` (or `NODE_ENV=development`).
2. Your HTTP client **does not** override `Origin` header — browsers set this.
3. Do **not** set `Access-Control-*` headers on the frontend request; they are response headers.
4. If you see a 403 on OPTIONS, ensure you're using the latest `server.js` that has `cors()` before custom `corsSecurity` middleware.

### "I keep getting MISSING_FIELDS on register even though I'm sending everything"

Send `userType`, not `user_type`; the server destructures camelCase.

### "Register returns 500 with REGISTRATION_ERROR"

Look at backend stdout. 99% of the time in a new environment the `organizations` or `users` tables are missing — run `npm run setup:db` to apply migrations, or execute the files in `migrations/` in order against your database.

### "Conflict POST returns 401 even with a token"

- Make sure your auth header is exactly `Authorization: Bearer <token>` (one space, exact case).
- If the server printed `INVALID_TOKEN` the token was truncated or encoded twice (e.g., URL-encoded by mistake).
- If the server printed `REVOKED_TOKEN` the login session was revoked (you called `/logout`, or the user changed their password).

### "Emotion / File upload endpoints fail with 413 (Payload Too Large)"

Increase `MAX_REQUEST_SIZE` in backend `.env` (default = 10 MB = 10485760 bytes) and restart the backend.

---

## 12. Security Checklist for Frontend Engineers

- ❌ **Never** log tokens (access or refresh) to `console.log` or analytics SDKs in production.
- ❌ **Never** store tokens in `localStorage` if your app uses SSO or is deployed across domains — prefer `HttpOnly` cookies if the backend is extended to issue them.
- ✅ Always call `/logout` when the user clicks "Sign out" — don't just drop the token locally; this revokes server-side sessions.
- ✅ Mask every password field with `autocomplete="current-password"` / `"new-password"` so password managers fill correctly.
- ✅ Use the `code` field from error responses to branch UI logic, **not** the human-readable `error` string. Error messages can change without notice.
- ✅ If your frontend redirects through OAuth integrations (Google / Outlook / Zoom), make sure the redirect landing page validates state parameters and calls the matching `/api/integrations/:provider/callback` on the backend instead of trusting tokens directly.

---

*If you extend this integration doc for a new feature, please also add a corresponding line-item entry to the table in §9 and include sample request/response.*
