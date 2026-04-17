# Firebase Backend Starter (Meerkat)

This folder provides a production-oriented starter for:
- Firestore security rules
- Cloud Function invite endpoint

## 1. Prerequisites

- Firebase project created
- Firestore enabled
- Blaze plan enabled (for Cloud Functions + external email API)
- Firebase CLI installed and logged in

## 2. Install function dependencies

Run from `backend/firebase/functions`:

```bash
npm install
npm run build
```

## 3. Set required function secrets / env

```bash
firebase functions:secrets:set RESEND_API_KEY
firebase functions:secrets:set INVITE_FROM_EMAIL
firebase functions:secrets:set INVITE_ACCEPT_URL
```

Examples:
- `INVITE_FROM_EMAIL`: `Meerkat <invites@yourdomain.com>`
- `INVITE_ACCEPT_URL`: `https://app.meerkatinnovations.ca/invite`

## 4. Deploy rules + functions

Run from `backend/firebase`:

```bash
firebase deploy --config firebase.json --only firestore:rules,firestore:indexes,functions
```

## 5. Callable function included

- `createOrganizationInvite`
  - Requires authenticated caller
  - Requires caller to be an account manager in:
    - `users/{uid}/organizationMemberships`
  - Writes invite doc to:
    - `organizations/{organizationID}/invitations/{normalizedEmail}`
  - Sends email through Resend API when secrets are configured

## 6. Important notes

- Current iOS app invite UI still has mail-app fallback.
- This backend starter is ready to wire into app-side callable invocations.
- Firestore rules here are strict owner-first defaults. Expand rules for full multi-user read/write as you complete invitation acceptance and membership activation flow.
