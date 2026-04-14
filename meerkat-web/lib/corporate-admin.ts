"use client";

import { httpsCallable } from "firebase/functions";
import { functions } from "@/lib/firebase";
import { resetPassword } from "@/lib/auth";
import type { OrganizationPermission, OrganizationRole } from "@/lib/firestore";

type UpsertCorporateInviteInput = {
  organizationID: string;
  emailAddress: string;
  displayName: string;
  role: OrganizationRole;
  assignedVehicleIDs: string[];
  assignedDriverID?: string;
  permissions: OrganizationPermission[];
  memberID?: string;
};

export async function upsertCorporateInvite(input: UpsertCorporateInviteInput) {
  const callable = httpsCallable<
    UpsertCorporateInviteInput,
    { emailAddress: string; memberID: string; uid: string }
  >(functions, "upsertCorporateInvite");

  const response = await callable(input);
  await resetPassword(response.data.emailAddress);
  return response.data;
}

export async function disableCorporateMember(input: {
  organizationID: string;
  memberID: string;
}) {
  const callable = httpsCallable<
    { organizationID: string; memberID: string },
    { memberID: string }
  >(functions, "disableCorporateMember");

  const response = await callable(input);
  return response.data;
}
