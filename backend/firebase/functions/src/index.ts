import {onCall, HttpsError} from "firebase-functions/v2/https";
import {setGlobalOptions} from "firebase-functions/v2";
import * as admin from "firebase-admin";

admin.initializeApp();
setGlobalOptions({region: "us-central1", maxInstances: 10});

type CreateOrganizationInviteRequest = {
    organizationID: string;
    inviteeEmail: string;
    displayName?: string;
};

function normalizeEmail(value: string): string {
    return value.trim().toLowerCase();
}

function requireString(value: unknown, fieldName: string): string {
    if (typeof value !== "string" || value.trim().isEmpty) {
        throw new HttpsError("invalid-argument", `${fieldName} is required.`);
    }
    return value.trim();
}

async function requesterIsAccountManager(
    uid: string,
    organizationID: string,
): Promise<boolean> {
    const membershipSnapshot = await admin
        .firestore()
        .collection("users")
        .doc(uid)
        .collection("organizationMemberships")
        .where("organizationID", "==", organizationID)
        .where("role", "==", "accountManager")
        .where("status", "in", ["active", "invited"])
        .limit(1)
        .get();

    return !membershipSnapshot.empty;
}

async function sendInviteEmail(
    inviteeEmail: string,
    inviteeName: string,
    organizationName: string,
    invitationID: string,
): Promise<void> {
    const resendApiKey = process.env.RESEND_API_KEY;
    const fromEmail = process.env.INVITE_FROM_EMAIL;
    const acceptBaseUrl = process.env.INVITE_ACCEPT_URL;

    if (!resendApiKey || !fromEmail || !acceptBaseUrl) {
        console.warn("Invite email skipped. Missing RESEND_API_KEY, INVITE_FROM_EMAIL, or INVITE_ACCEPT_URL.");
        return;
    }

    const acceptUrl = `${acceptBaseUrl.replace(/\/$/, "")}?invitation=${encodeURIComponent(invitationID)}`;
    const html = `
        <p>Hi ${inviteeName || "there"},</p>
        <p>You have been invited to join <strong>${organizationName}</strong> on Meerkat Mileage Tracker.</p>
        <p><a href="${acceptUrl}">Accept invitation</a></p>
        <p>If you already have the app, sign in with ${inviteeEmail}.</p>
    `;

    const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
            "Authorization": `Bearer ${resendApiKey}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            from: fromEmail,
            to: [inviteeEmail],
            subject: `Invitation to join ${organizationName} on Meerkat Mileage Tracker`,
            html,
        }),
    });

    if (!response.ok) {
        const body = await response.text();
        throw new HttpsError("internal", `Resend failed: ${response.status} ${body}`);
    }
}

export const createOrganizationInvite = onCall(async (request) => {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication is required.");
    }

    const data = request.data as CreateOrganizationInviteRequest;
    const organizationID = requireString(data.organizationID, "organizationID");
    const inviteeEmail = normalizeEmail(requireString(data.inviteeEmail, "inviteeEmail"));
    const displayName = (data.displayName ?? "").trim();

    const canManage = await requesterIsAccountManager(request.auth.uid, organizationID);
    if (!canManage) {
        throw new HttpsError("permission-denied", "Only account managers can invite employees.");
    }

    const organizationRef = admin.firestore().collection("organizations").doc(organizationID);
    const organizationSnapshot = await organizationRef.get();
    if (!organizationSnapshot.exists) {
        throw new HttpsError("not-found", "Organization not found.");
    }

    const organizationName = (organizationSnapshot.get("name") as string | undefined) ?? "Your organization";
    const invitationRef = organizationRef.collection("invitations").doc(inviteeEmail);

    await invitationRef.set({
        organizationID,
        inviteeEmail,
        displayName,
        status: "pending",
        invitedByUID: request.auth.uid,
        invitedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    await sendInviteEmail(inviteeEmail, displayName, organizationName, invitationRef.id);

    return {
        ok: true,
        invitationID: invitationRef.id,
        inviteeEmail,
    };
});
