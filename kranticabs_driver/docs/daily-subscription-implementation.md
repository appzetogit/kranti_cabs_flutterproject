# Daily Subscription — driver app implementation

A driver buys a pass for the day instead of paying commission on each trip.
₹29 for bike and auto, ₹49 for a car. The backend is live; this document is
the app side.

Nothing here needs a backend change. If something below does not match what
the API returns, trust the API and say so — do not work around it in the app.

---

## 1. The one rule that trips people up

**The pass is a clock window, not 24 hours from payment.**

It always ends at **6:00 AM IST** the next morning, whatever time it was
bought. Buy at 12 PM → valid until 6 AM tomorrow. Buy at 5 AM → valid until
6 AM **this** morning, one hour later.

Never compute the expiry in the app. The API returns `expiresAt`; show that.
The 6 AM hour is an admin setting and can change.

---

## 2. API

Base path: `/api/v1/drivers`. All three need the driver's bearer token.

### GET `/subscription`

Everything the screen needs, in one call.

```json
{
  "success": true,
  "data": {
    "enabled": true,
    "required": false,
    "status": "active",
    "expiresAt": "2026-09-29T00:30:00.000Z",
    "currentCycle": { "startsAt": "...", "expiresAt": "..." },
    "paymentMethods": ["wallet", "gateway"],
    "onExpiry": "commission",
    "subscription": {
      "id": "...",
      "planName": "Daily Pass - Car",
      "amount": 49,
      "startsAt": "...",
      "expiresAt": "...",
      "paymentMethod": "wallet",
      "vehicleClasses": ["car"]
    },
    "plans": [
      {
        "id": "...",
        "name": "Daily Pass - Car",
        "amount": 49,
        "vehicleClasses": ["car"],
        "description": "₹49 per day, valid until 6:00 AM the next day",
        "howItWorks": "Pay once for the day. No commission and no wallet minimum until 6:00 AM tomorrow."
      }
    ]
  }
}
```

Field notes:

- `enabled` — false means the whole feature is off for this city. **Hide the
  menu entry entirely.** Do not show a disabled button.
- `required` — true means a pass is mandatory; a driver without one gets no
  ride requests. Say so plainly on the screen.
- `status` — `"active"` or `"expired"`. This is the badge.
- `subscription` — null when expired.
- `plans` — usually one. A driver registered for several vehicle types
  normally sees only the dearest plan, because the admin default is that it
  covers all their vehicles. If the admin switches to `driver_choice` they see
  several: render them as a list and let the driver pick. **Do not hardcode
  ₹29/₹49 anywhere** — the admin can change both.
- `paymentMethods` — which buttons to offer: `wallet`, `gateway`, or both.
- `onExpiry` — `"commission"` (keeps working, pays commission) or `"block"`
  (no rides until renewed). This changes the wording of the expired state, so
  read it rather than assuming.

### POST `/subscription/purchase`

```json
{ "planId": "<plan id>", "paymentMethod": "wallet" }
```

On success the response carries the refreshed status, so update the screen
from `data.status` without calling GET again:

```json
{ "success": true, "data": { "subscription": {...}, "requiresPayment": false, "amount": 49, "status": { ... } } }
```

Errors to handle by message, all with `success: false`:

| Status | Means | What the driver should see |
|---|---|---|
| 400 | Not enough wallet balance | Offer to top up (below) |
| 400 | Subscriptions not enabled / method not enabled | Refresh the screen; settings changed |
| 409 | Already active this cycle | Refresh; they already have it |

### GET `/subscription/history?limit=30`

Past passes, newest first: `planName`, `amount`, `startsAt`, `expiresAt`,
`paidAt`, `paymentMethod`, `tripsCovered`, `commissionWaived`.

`commissionWaived` is what the pass saved them — worth showing: "You saved
₹210 on 14 trips."

---

## 3. Paying

**Wallet** (`paymentMethod: "wallet"`) is one call and settles instantly.

**UPI / card** — do **not** build a new gateway flow. Reuse the wallet top-up
the app already has:

1. Driver taps "Pay ₹49 by UPI".
2. Run the existing top-up for the shortfall (`amount − wallet balance`)
   through `/wallet/top-up/razorpay/order` and its verify step, exactly as the
   wallet screen does today.
3. On success, call `/subscription/purchase` with `paymentMethod: "wallet"`.

That keeps one verified payment path. The API accepts `"razorpay"` and
`"phonepe"` for a future direct payment, but those create an **unpaid** pass
that only activates when the gateway confirms — do not use them yet.

---

## 4. The screen

`Daily Subscription`, reachable from the driver menu or home.

**Active**

- Green "Active" badge.
- "Valid until 6:00 AM, 29 Sep" — formatted from `expiresAt`, in IST.
- A live "expires in 5h 12m" line is nice; recompute from `expiresAt`, never
  from a stored duration.
- What it gives them: no commission on trips, no wallet minimum.
- Today's benefit from `tripsCovered` / `commissionWaived` if you show it.
- No buy button — a second purchase in the same cycle is refused by the API.

**Expired**

- Grey "Expired" badge.
- The plan card: name, ₹ amount, and "valid until 6:00 AM tomorrow".
- A clear **Renew Subscription** / **Subscribe** button.
- If `required` is true, or `onExpiry` is `"block"`: "You will not receive
  ride requests until you subscribe."
- If `onExpiry` is `"commission"`: "Without a pass, commission applies to each
  trip as usual."

**Reminders**

- Re-fetch when the screen opens, after a purchase, and when the app returns
  to the foreground — a pass can lapse while the app sits open overnight.
- When `expiresAt` passes with the app open, flip to the expired state without
  waiting for a restart.

---

## 5. Things to get right

- **Never cache the status across a cycle boundary.** 6 AM is when this
  matters and it is exactly when a stale cache lies.
- **All times from the API are UTC ISO strings.** Convert to IST for display.
  `expiresAt` of `2026-09-29T00:30:00.000Z` is 6:00 AM IST — if your screen
  shows 12:30 AM, the conversion is missing.
- **Do not block going online in the app.** The server decides who gets ride
  requests. The app's job is to explain why they are not getting any.
- **Do not show the feature when `enabled` is false.**
- A driver with an active pass whose wallet is negative is fine — that is the
  point of the pass. Do not add a balance check of your own.

---

## 6. How to test

1. Admin panel → Settings → Driver Subscription: mode is "Both".
2. Driver with wallet balance ≥ ₹49 → buy → status flips to Active, expiry
   reads 6:00 AM tomorrow IST.
3. Buy again → 409, screen stays Active.
4. Drop the driver's wallet below the minimum → they still receive rides.
5. Complete a trip → the driver's earning is the full fare (minus the rider
   platform fee if the city charges one), no commission deducted.
6. Set the driver's pass `expiresAt` to the past in the database → screen
   flips to Expired and Renew appears.

Questions on the API: ask before adapting around it.
