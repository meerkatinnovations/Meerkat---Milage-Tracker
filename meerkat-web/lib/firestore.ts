import {
  addDoc,
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where
} from "firebase/firestore";
import { db } from "@/lib/firebase";

export type UserProfile = {
  email?: string;
  displayName?: string;
  selectedCountry?: string;
  preferredCurrency?: string;
  unitSystem?: string;
  activeVehicleID?: string;
  activeDriverID?: string;
  accountSubscriptionType?: "personal" | "business" | string;
  hasBusinessSubscription?: boolean;
  businessProfile?: unknown;
};

export type TripRecord = {
  id: string;
  ownerUID?: string;
  ownerEmail?: string;
  name?: string;
  tripType?: string;
  vehicleProfileName?: string;
  driverName?: string;
  startAddress?: string;
  endAddress?: string;
  details?: string;
  odometerStart?: number;
  odometerEnd?: number;
  distanceMeters?: number;
  date?: { seconds: number };
  updatedAt?: { seconds: number };
};

export type VehicleRecord = {
  id: string;
  ownerUID?: string;
  ownerEmail?: string;
  displayName?: string;
  profileName?: string;
  make?: string;
  model?: string;
  numberPlate?: string;
  startingOdometerReading?: number;
  archived?: boolean;
  updatedAt?: { seconds: number };
};

export type DriverRecord = {
  id: string;
  ownerUID?: string;
  ownerEmail?: string;
  name?: string;
  displayName?: string;
  emailAddress?: string;
  archived?: boolean;
  updatedAt?: { seconds: number };
};

export type FuelRecord = {
  id: string;
  ownerUID?: string;
  ownerEmail?: string;
  station?: string;
  vehicleProfileName?: string;
  volume?: number;
  totalCost?: number;
  odometer?: number;
  receiptPath?: string;
  updatedAt?: { seconds: number };
};

export type MaintenanceRecord = {
  id: string;
  ownerUID?: string;
  ownerEmail?: string;
  shopName?: string;
  vehicleProfileName?: string;
  type?: string;
  otherDescription?: string;
  notes?: string;
  totalCost?: number;
  odometer?: number;
  receiptPath?: string;
  reminderEnabled?: boolean;
  nextServiceOdometer?: number;
  updatedAt?: { seconds: number };
};

export type OrganizationPlan = "corporateMonthly" | "corporateYearly";
export type OrganizationBillingStatus = "pendingPayment" | "active" | "pastDue" | "canceled" | "trial";
export type OrganizationRole = "accountManager" | "employee";
export type OrganizationMemberStatus = "invited" | "active" | "removed";
export type OrganizationPermission =
  | "deleteTrips"
  | "deleteFuelEntries"
  | "deleteMaintenanceRecords"
  | "exportLogs"
  | "viewLogs"
  | "manageVehicles"
  | "manageDrivers"
  | "manageMembers";

export type OrganizationRecord = {
  id: string;
  name: string;
  plan: OrganizationPlan;
  billingStatus: OrganizationBillingStatus;
  expiresAt?: { seconds: number };
  createdAt?: { seconds: number };
  createdByUID?: string;
};

export type OrganizationMemberRecord = {
  id: string;
  uid?: string;
  organizationID: string;
  emailAddress: string;
  emailAddressLower: string;
  displayName?: string;
  role: OrganizationRole;
  status: OrganizationMemberStatus;
  assignedVehicleIDs?: string[];
  assignedDriverID?: string;
  permissions?: OrganizationPermission[];
  createdAt?: { seconds: number };
  invitedAt?: { seconds: number };
  activatedAt?: { seconds: number };
  removedAt?: { seconds: number };
};

export type OrganizationContext = {
  organization: OrganizationRecord;
  membership: OrganizationMemberRecord;
};

type OwnedRecord = {
  id: string;
  ownerUID?: string;
  ownerEmail?: string;
};

export async function fetchUserProfile(uid: string) {
  const snapshot = await getDoc(doc(db, "users", uid));
  return (snapshot.data() ?? null) as UserProfile | null;
}

function normalizeEmail(value: string) {
  return value.trim().toLowerCase();
}

async function upsertUserMembershipMirror(
  uid: string,
  organizationID: string,
  membership: {
    emailAddress: string;
    displayName?: string;
    role: OrganizationRole;
    status: OrganizationMemberStatus;
    assignedVehicleIDs: string[];
    assignedDriverID?: string;
    permissions: OrganizationPermission[];
  }
) {
  await setDoc(
    doc(db, "users", uid, "organizationMemberships", organizationID),
    {
      organizationID,
      uid,
      emailAddress: membership.emailAddress,
      emailAddressLower: normalizeEmail(membership.emailAddress),
      displayName: membership.displayName ?? membership.emailAddress,
      role: membership.role,
      status: membership.status,
      assignedVehicleIDs: membership.assignedVehicleIDs,
      assignedDriverID: membership.assignedDriverID ?? null,
      permissions: membership.permissions,
      updatedAt: serverTimestamp()
    },
    { merge: true }
  );
}

export async function fetchCollection<T>(uid: string, collectionName: string) {
  const snapshot = await getDocs(
    query(collection(db, "users", uid, collectionName), orderBy("updatedAt", "desc"))
  );
  return snapshot.docs.map((entry) => entry.data() as T);
}

export async function fetchCollectionUnordered<T>(uid: string, collectionName: string) {
  const snapshot = await getDocs(collection(db, "users", uid, collectionName));
  return snapshot.docs.map((entry) => entry.data() as T);
}

export async function fetchOrganizationContextForUser(
  uid: string,
  emailAddress: string,
  displayName?: string | null
) {
  const normalizedEmail = normalizeEmail(emailAddress);
  if (!normalizedEmail) {
    return null;
  }

  const membershipSnapshot = await getDocs(
    query(
      collectionGroup(db, "members"),
      where("emailAddressLower", "==", normalizedEmail)
    )
  );

  const candidateMemberships = membershipSnapshot.docs
    .map((entry) => ({
      id: entry.id,
      ref: entry.ref,
      ...entry.data()
    } as OrganizationMemberRecord & { ref: typeof entry.ref }))
    .filter((entry) => entry.status !== "removed");

  if (candidateMemberships.length === 0) {
    return null;
  }

  const selectedMembership =
    candidateMemberships.find((entry) => entry.uid === uid && entry.status === "active") ??
    candidateMemberships.find((entry) => entry.status === "active") ??
    candidateMemberships[0];

  if (selectedMembership.uid !== uid || !selectedMembership.displayName || selectedMembership.status === "invited") {
    await updateDoc(selectedMembership.ref, {
      uid,
      displayName: displayName ?? selectedMembership.displayName ?? emailAddress,
      status: selectedMembership.status === "invited" ? "active" : selectedMembership.status,
      activatedAt: serverTimestamp()
    });
  }

  await upsertUserMembershipMirror(uid, selectedMembership.organizationID, {
    emailAddress,
    displayName: displayName ?? selectedMembership.displayName ?? emailAddress,
    role: selectedMembership.role,
    status: selectedMembership.status === "invited" ? "active" : selectedMembership.status,
    assignedVehicleIDs: selectedMembership.assignedVehicleIDs ?? [],
    assignedDriverID: selectedMembership.assignedDriverID,
    permissions: selectedMembership.permissions ?? []
  });

  const organizationSnapshot = await getDoc(doc(db, "organizations", selectedMembership.organizationID));
  if (!organizationSnapshot.exists()) {
    return null;
  }

  return {
    organization: {
      id: organizationSnapshot.id,
      ...organizationSnapshot.data()
    } as OrganizationRecord,
    membership: {
      ...selectedMembership,
      uid,
      displayName: displayName ?? selectedMembership.displayName ?? emailAddress,
      status: selectedMembership.status === "invited" ? "active" : selectedMembership.status
    }
  } satisfies OrganizationContext;
}

export async function createOrganizationForManager(input: {
  uid: string;
  emailAddress: string;
  displayName?: string;
  organizationName: string;
  plan: OrganizationPlan;
}) {
  const createdAt = serverTimestamp();
  const organizationRef = await addDoc(collection(db, "organizations"), {
    name: input.organizationName.trim(),
    plan: input.plan,
    billingStatus: "pendingPayment",
    expiresAt: null,
    createdAt,
    createdByUID: input.uid
  });

  await setDoc(doc(db, "organizations", organizationRef.id, "members", input.uid), {
    uid: input.uid,
    organizationID: organizationRef.id,
    emailAddress: input.emailAddress,
    emailAddressLower: normalizeEmail(input.emailAddress),
    displayName: input.displayName ?? input.emailAddress,
    role: "accountManager",
    status: "active",
    assignedVehicleIDs: [],
    permissions: [
      "deleteTrips",
      "deleteFuelEntries",
      "deleteMaintenanceRecords",
      "exportLogs",
      "viewLogs",
      "manageVehicles",
      "manageDrivers",
      "manageMembers"
    ],
    createdAt,
    invitedAt: createdAt,
    activatedAt: createdAt
  });

  await upsertUserMembershipMirror(input.uid, organizationRef.id, {
    emailAddress: input.emailAddress,
    displayName: input.displayName ?? input.emailAddress,
    role: "accountManager",
    status: "active",
    assignedVehicleIDs: [],
    permissions: [
      "deleteTrips",
      "deleteFuelEntries",
      "deleteMaintenanceRecords",
      "exportLogs",
      "viewLogs",
      "manageVehicles",
      "manageDrivers",
      "manageMembers"
    ]
  });

  return organizationRef.id;
}

export async function fetchOrganizationMembers(organizationID: string) {
  const snapshot = await getDocs(
    query(collection(db, "organizations", organizationID, "members"), orderBy("emailAddressLower", "asc"))
  );
  return snapshot.docs.map((entry) => ({
    id: entry.id,
    ...entry.data()
  } as OrganizationMemberRecord));
}

export async function resolveVisibleUserIDs(
  currentUID: string,
  organizationContext: OrganizationContext | null
) {
  if (!organizationContext) {
    return [currentUID];
  }

  if (organizationContext.membership.role !== "accountManager") {
    return [currentUID];
  }

  const members = await fetchOrganizationMembers(organizationContext.organization.id);
  return members
    .filter((member) => member.status === "active" && member.uid)
    .map((member) => member.uid as string);
}

export async function fetchScopedCollection<T extends OwnedRecord>(
  currentUID: string,
  organizationContext: OrganizationContext | null,
  collectionName: string
) {
  if (organizationContext) {
    const organizationRecords = await fetchOrganizationCollection<T>(
      organizationContext,
      currentUID,
      collectionName
    );
    if (organizationRecords.length > 0) {
      return organizationRecords;
    }
  }

  const visibleUserIDs = await resolveVisibleUserIDs(currentUID, organizationContext);
  const sortedUserIDs = Array.from(new Set(visibleUserIDs)).sort();
  const snapshots = await Promise.all(
    sortedUserIDs.map(async (uid) => {
      const records = await fetchCollection<T>(uid, collectionName);
      const profile = await fetchUserProfile(uid);
      return records.map((record) => ({
        ...record,
        ownerUID: uid,
        ownerEmail: profile?.email
      }));
    })
  );

  return snapshots.flat();
}

export async function fetchOrganizationCollection<T extends OwnedRecord>(
  organizationContext: OrganizationContext,
  currentUID: string,
  collectionName: string
) {
  const snapshot = await getDocs(
    query(
      collection(db, "organizations", organizationContext.organization.id, collectionName),
      orderBy("updatedAt", "desc")
    )
  );

  let records = snapshot.docs.map((entry) => ({
    id: entry.id,
    ...entry.data()
  } as T));

  if (organizationContext.membership.role !== "accountManager") {
    if (collectionName === "vehicles") {
      const assignedVehicleIDs = new Set(organizationContext.membership.assignedVehicleIDs ?? []);
      records = records.filter((record) => assignedVehicleIDs.has(record.id));
    } else if (collectionName === "drivers") {
      const assignedDriverID = organizationContext.membership.assignedDriverID;
      records = records.filter((record) => !assignedDriverID || record.id === assignedDriverID);
    } else {
      records = records.filter((record) => record.ownerUID === currentUID);
    }
  }

  return records;
}

export async function saveOrganizationMember(
  organizationID: string,
  member: {
    id?: string;
    emailAddress: string;
    displayName: string;
    role: OrganizationRole;
    assignedVehicleIDs: string[];
    assignedDriverID?: string;
    permissions: OrganizationPermission[];
  }
) {
  const memberID = member.id ?? normalizeEmail(member.emailAddress).replace(/[^a-z0-9]/g, "_");
  const memberRef = doc(db, "organizations", organizationID, "members", memberID);
  const existingSnapshot = await getDoc(memberRef);
  const currentData = existingSnapshot.data() as Partial<OrganizationMemberRecord> | undefined;

  await setDoc(
    memberRef,
    {
      id: memberID,
      organizationID,
      emailAddress: member.emailAddress.trim(),
      emailAddressLower: normalizeEmail(member.emailAddress),
      displayName: member.displayName.trim(),
      role: member.role,
      status: currentData?.status === "active" ? "active" : "invited",
      uid: currentData?.uid ?? null,
      assignedVehicleIDs: member.assignedVehicleIDs,
      assignedDriverID: member.assignedDriverID ?? null,
      permissions: member.permissions,
      createdAt: currentData?.createdAt ?? serverTimestamp(),
      invitedAt: currentData?.invitedAt ?? serverTimestamp(),
      activatedAt: currentData?.activatedAt ?? null,
      removedAt: null
    },
    { merge: true }
  );

  if (currentData?.uid) {
    await upsertUserMembershipMirror(currentData.uid, organizationID, {
      emailAddress: member.emailAddress,
      displayName: member.displayName,
      role: member.role,
      status: currentData.status === "active" ? "active" : "invited",
      assignedVehicleIDs: member.assignedVehicleIDs,
      assignedDriverID: member.assignedDriverID,
      permissions: member.permissions
    });
  }

  return memberID;
}

export async function removeOrganizationMember(organizationID: string, memberID: string) {
  const memberRef = doc(db, "organizations", organizationID, "members", memberID);
  const memberSnapshot = await getDoc(memberRef);
  const memberData = memberSnapshot.data() as OrganizationMemberRecord | undefined;

  await updateDoc(memberRef, {
    status: "removed",
    removedAt: serverTimestamp()
  });

  if (memberData?.uid) {
    await setDoc(
      doc(db, "users", memberData.uid, "organizationMemberships", organizationID),
      {
        status: "removed",
        updatedAt: serverTimestamp()
      },
      { merge: true }
    );
  }
}

export async function fetchRecordsForUserIDs<T>(userIDs: string[], collectionName: string) {
  const snapshots = await Promise.all(
    userIDs.map(async (uid) => {
      const entries = await fetchCollection<T>(uid, collectionName);
      return entries;
    })
  );

  return snapshots.flat();
}

export type TripUpdateInput = {
  id: string;
  name: string;
  tripType: string;
  vehicleProfileName: string;
  driverName: string;
  startAddress: string;
  endAddress: string;
  details: string;
  odometerStart: number;
  odometerEnd: number;
  distanceMeters: number;
  date: Date;
};

export type VehicleUpdateInput = {
  id: string;
  profileName: string;
  make: string;
  model: string;
  color: string;
  numberPlate: string;
  startingOdometerReading: number;
  archived: boolean;
};

export type FuelUpdateInput = {
  id: string;
  station: string;
  vehicleProfileName: string;
  volume: number;
  totalCost: number;
  odometer: number;
};

export type MaintenanceUpdateInput = {
  id: string;
  shopName: string;
  vehicleProfileName: string;
  type: string;
  otherDescription: string;
  notes: string;
  totalCost: number;
  odometer: number;
  reminderEnabled: boolean;
  nextServiceOdometer?: number;
};

export async function saveTrip(uid: string, trip: TripUpdateInput) {
  await setDoc(
    doc(db, "users", uid, "trips", trip.id),
    {
      id: trip.id,
      name: trip.name,
      tripType: trip.tripType,
      vehicleProfileName: trip.vehicleProfileName,
      driverName: trip.driverName,
      startAddress: trip.startAddress,
      endAddress: trip.endAddress,
      details: trip.details,
      odometerStart: trip.odometerStart,
      odometerEnd: trip.odometerEnd,
      distanceMeters: trip.distanceMeters,
      date: Timestamp.fromDate(trip.date),
      updatedAt: serverTimestamp()
    },
    { merge: true }
  );
}

export async function deleteTrip(uid: string, tripID: string) {
  await deleteDoc(doc(db, "users", uid, "trips", tripID));
}

export async function saveVehicle(uid: string, vehicle: VehicleUpdateInput) {
  await setDoc(
    doc(db, "users", uid, "vehicles", vehicle.id),
    {
      id: vehicle.id,
      profileName: vehicle.profileName,
      displayName: vehicle.profileName || [vehicle.make, vehicle.model].filter(Boolean).join(" "),
      make: vehicle.make,
      model: vehicle.model,
      color: vehicle.color,
      numberPlate: vehicle.numberPlate,
      startingOdometerReading: vehicle.startingOdometerReading,
      archived: vehicle.archived,
      updatedAt: serverTimestamp()
    },
    { merge: true }
  );
}

export async function saveFuelEntry(uid: string, entry: FuelUpdateInput) {
  await setDoc(
    doc(db, "users", uid, "fuelEntries", entry.id),
    {
      id: entry.id,
      station: entry.station,
      vehicleProfileName: entry.vehicleProfileName,
      volume: entry.volume,
      totalCost: entry.totalCost,
      odometer: entry.odometer,
      updatedAt: serverTimestamp()
    },
    { merge: true }
  );
}

export async function saveMaintenanceRecord(uid: string, record: MaintenanceUpdateInput) {
  await setDoc(
    doc(db, "users", uid, "maintenanceRecords", record.id),
    {
      id: record.id,
      shopName: record.shopName,
      vehicleProfileName: record.vehicleProfileName,
      type: record.type,
      otherDescription: record.otherDescription,
      notes: record.notes,
      totalCost: record.totalCost,
      odometer: record.odometer,
      reminderEnabled: record.reminderEnabled,
      nextServiceOdometer: record.nextServiceOdometer ?? null,
      updatedAt: serverTimestamp()
    },
    { merge: true }
  );
}
