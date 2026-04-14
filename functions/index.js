const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

admin.initializeApp();

const db = admin.firestore();
const auth = admin.auth();

function normalizeEmail(value) {
  return String(value || "").trim().toLowerCase();
}

async function requireManager(authContext, organizationID) {
  if (!authContext) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }

  const membershipRef = db
    .collection("organizations")
    .doc(organizationID)
    .collection("members")
    .doc(authContext.uid);

  const membershipSnapshot = await membershipRef.get();
  if (!membershipSnapshot.exists) {
    throw new HttpsError("permission-denied", "No membership found for this organization.");
  }

  const membership = membershipSnapshot.data();
  if (membership.status !== "active" || membership.role !== "accountManager") {
    throw new HttpsError("permission-denied", "Account manager access is required.");
  }

  return membership;
}

exports.upsertCorporateInvite = onCall(async (request) => {
  const {
    organizationID,
    emailAddress,
    displayName,
    role,
    assignedVehicleIDs = [],
    assignedDriverID = null,
    permissions = [],
    memberID = null
  } = request.data || {};

  if (!organizationID || !emailAddress || !displayName || !role) {
    throw new HttpsError("invalid-argument", "organizationID, emailAddress, displayName, and role are required.");
  }

  await requireManager(request.auth, organizationID);

  const normalizedEmail = normalizeEmail(emailAddress);
  let userRecord;

  try {
    userRecord = await auth.getUserByEmail(normalizedEmail);
  } catch (error) {
    if (error.code === "auth/user-not-found") {
      userRecord = await auth.createUser({
        email: normalizedEmail,
        emailVerified: false,
        displayName: String(displayName).trim(),
        password: admin.firestore().app.options.projectId + "-" + Date.now(),
        disabled: false
      });
    } else {
      throw error;
    }
  }

  if (userRecord.disabled) {
    await auth.updateUser(userRecord.uid, { disabled: false });
  }

  const resolvedMemberID = memberID || userRecord.uid;
  const memberRef = db
    .collection("organizations")
    .doc(organizationID)
    .collection("members")
    .doc(resolvedMemberID);

  const existingSnapshot = await memberRef.get();
  const existingData = existingSnapshot.exists ? existingSnapshot.data() : null;

  await memberRef.set(
    {
      id: resolvedMemberID,
      uid: userRecord.uid,
      organizationID,
      emailAddress: normalizedEmail,
      emailAddressLower: normalizedEmail,
      displayName: String(displayName).trim(),
      role,
      status: existingData?.status === "active" ? "active" : "invited",
      assignedVehicleIDs,
      assignedDriverID,
      permissions,
      createdAt: existingData?.createdAt || admin.firestore.FieldValue.serverTimestamp(),
      invitedAt: admin.firestore.FieldValue.serverTimestamp(),
      activatedAt: existingData?.activatedAt || null,
      removedAt: null
    },
    { merge: true }
  );

  await db
    .collection("users")
    .doc(userRecord.uid)
    .collection("organizationMemberships")
    .doc(organizationID)
    .set(
      {
        organizationID,
        uid: userRecord.uid,
        emailAddress: normalizedEmail,
        emailAddressLower: normalizedEmail,
        displayName: String(displayName).trim(),
        role,
        status: existingData?.status === "active" ? "active" : "invited",
        assignedVehicleIDs,
        assignedDriverID,
        permissions,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      },
      { merge: true }
    );

  return {
    memberID: resolvedMemberID,
    uid: userRecord.uid,
    emailAddress: normalizedEmail
  };
});

exports.disableCorporateMember = onCall(async (request) => {
  const { organizationID, memberID } = request.data || {};

  if (!organizationID || !memberID) {
    throw new HttpsError("invalid-argument", "organizationID and memberID are required.");
  }

  await requireManager(request.auth, organizationID);

  const memberRef = db
    .collection("organizations")
    .doc(organizationID)
    .collection("members")
    .doc(memberID);

  const memberSnapshot = await memberRef.get();
  if (!memberSnapshot.exists) {
    throw new HttpsError("not-found", "Member not found.");
  }

  const member = memberSnapshot.data();

  await memberRef.set(
    {
      status: "removed",
      removedAt: admin.firestore.FieldValue.serverTimestamp()
    },
    { merge: true }
  );

  if (member.uid) {
    await auth.updateUser(member.uid, { disabled: true });
    await db
      .collection("users")
      .doc(member.uid)
      .collection("organizationMemberships")
      .doc(organizationID)
      .set(
        {
          status: "removed",
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        },
        { merge: true }
      );
  }

  return { memberID };
});
