"use client";

import { useEffect, useMemo, useState } from "react";
import { AuthGuard } from "@/components/auth-guard";
import { NavShell } from "@/components/nav-shell";
import { useAuth } from "@/components/auth-provider";
import { disableCorporateMember, upsertCorporateInvite } from "@/lib/corporate-admin";
import {
  createOrganizationForManager,
  DriverRecord,
  OrganizationBillingStatus,
  fetchScopedCollection,
  fetchOrganizationMembers,
  OrganizationMemberRecord,
  OrganizationPermission,
  OrganizationPlan,
  TripRecord,
  VehicleRecord
} from "@/lib/firestore";

const allPermissions: OrganizationPermission[] = [
  "deleteTrips",
  "deleteFuelEntries",
  "deleteMaintenanceRecords",
  "exportLogs",
  "viewLogs",
  "manageVehicles",
  "manageDrivers",
  "manageMembers"
];

function labelForPermission(permission: OrganizationPermission) {
  switch (permission) {
    case "deleteTrips":
      return "Delete trips";
    case "deleteFuelEntries":
      return "Delete fuel-ups";
    case "deleteMaintenanceRecords":
      return "Delete maintenance";
    case "exportLogs":
      return "Download logs";
    case "viewLogs":
      return "View logs";
    case "manageVehicles":
      return "Manage vehicles";
    case "manageDrivers":
      return "Manage drivers";
    case "manageMembers":
      return "Manage members";
  }
}

function labelForBillingStatus(status: OrganizationBillingStatus) {
  switch (status) {
    case "pendingPayment":
      return "Pending Payment";
    case "active":
      return "Active";
    case "pastDue":
      return "Past Due";
    case "canceled":
      return "Canceled";
    case "trial":
      return "Trial";
  }
}

function normalizeText(value?: string) {
  return (value ?? "").trim().toLowerCase();
}

function formatDistance(distanceMeters: number) {
  const kilometers = distanceMeters / 1000;
  return new Intl.NumberFormat(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 1
  }).format(kilometers);
}

type MemberFormState = {
  id?: string;
  emailAddress: string;
  displayName: string;
  role: "accountManager" | "employee";
  assignedVehicleIDs: string[];
  permissions: OrganizationPermission[];
};

const emptyMemberForm: MemberFormState = {
  emailAddress: "",
  displayName: "",
  role: "employee",
  assignedVehicleIDs: [],
  permissions: ["viewLogs"]
};

export default function OrganizationPage() {
  const { user, organizationContext } = useAuth();
  const uid = user?.uid;
  const emailAddress = user?.email;
  const [organizationName, setOrganizationName] = useState("");
  const [organizationPlan, setOrganizationPlan] = useState<OrganizationPlan>("corporateMonthly");
  const [members, setMembers] = useState<OrganizationMemberRecord[]>([]);
  const [vehicles, setVehicles] = useState<VehicleRecord[]>([]);
  const [drivers, setDrivers] = useState<DriverRecord[]>([]);
  const [trips, setTrips] = useState<TripRecord[]>([]);
  const [selectedVehicleID, setSelectedVehicleID] = useState("all");
  const [selectedDriverID, setSelectedDriverID] = useState("all");
  const [memberForm, setMemberForm] = useState<MemberFormState>(emptyMemberForm);
  const [status, setStatus] = useState("");
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    if (!uid) {
      return;
    }
    const safeUID = uid;

    async function loadPortalData() {
      const [nextVehicles, nextDrivers, nextTrips] = await Promise.all([
        fetchScopedCollection<VehicleRecord>(safeUID, organizationContext, "vehicles"),
        fetchScopedCollection<DriverRecord>(safeUID, organizationContext, "drivers"),
        fetchScopedCollection<TripRecord>(safeUID, organizationContext, "trips")
      ]);
      setVehicles(nextVehicles);
      setDrivers(nextDrivers);
      setTrips(nextTrips);
    }

    void loadPortalData();
  }, [organizationContext, uid]);

  useEffect(() => {
    if (!organizationContext?.organization.id) {
      setMembers([]);
      return;
    }

    void fetchOrganizationMembers(organizationContext.organization.id).then(setMembers);
  }, [organizationContext?.organization.id]);

  const isManager = organizationContext?.membership.role === "accountManager";

  const assignedVehicleNames = useMemo(() => {
    const names = new Map<string, string>();
    for (const vehicle of vehicles) {
      names.set(vehicle.id, vehicle.displayName || vehicle.profileName || vehicle.id);
    }
    return names;
  }, [vehicles]);

  const vehicleNameByID = useMemo(() => {
    const names = new Map<string, string>();
    for (const vehicle of vehicles) {
      names.set(vehicle.id, vehicle.displayName || vehicle.profileName || vehicle.id);
    }
    return names;
  }, [vehicles]);

  const driverFilterEntries = useMemo(() => {
    const entries = new Map<string, string>();

    for (const driver of drivers) {
      entries.set(driver.id, driver.name || driver.displayName || driver.emailAddress || driver.id);
    }

    for (const member of members) {
      if (member.status !== "removed" && !entries.has(member.id)) {
        entries.set(member.id, member.displayName || member.emailAddress);
      }
    }

    return Array.from(entries, ([id, displayName]) => ({ id, displayName }));
  }, [drivers, members]);

  const filteredTrips = useMemo(() => {
    const selectedVehicleName = selectedVehicleID === "all"
      ? ""
      : normalizeText(vehicleNameByID.get(selectedVehicleID));
    const selectedDriverName = selectedDriverID === "all"
      ? ""
      : normalizeText(driverFilterEntries.find((entry) => entry.id === selectedDriverID)?.displayName);

    return trips.filter((trip) => {
      const vehicleMatches = selectedVehicleName
        ? normalizeText(trip.vehicleProfileName) === selectedVehicleName
        : true;
      const driverMatches = selectedDriverName
        ? normalizeText(trip.driverName) === selectedDriverName
        : true;
      return vehicleMatches && driverMatches;
    });
  }, [driverFilterEntries, selectedDriverID, selectedVehicleID, trips, vehicleNameByID]);

  const vehicleTripStats = useMemo(() => {
    return vehicles.map((vehicle) => {
      const vehicleName = normalizeText(vehicle.displayName || vehicle.profileName);
      const vehicleTrips = trips.filter((trip) => normalizeText(trip.vehicleProfileName) === vehicleName);
      const businessTrips = vehicleTrips.filter((trip) => trip.tripType === "business");
      const distanceMeters = vehicleTrips.reduce((totalDistance, trip) => totalDistance + (trip.distanceMeters ?? 0), 0);

      return {
        id: vehicle.id,
        displayName: vehicle.displayName || vehicle.profileName || vehicle.id,
        trips: vehicleTrips.length,
        businessTrips: businessTrips.length,
        distanceMeters
      };
    });
  }, [trips, vehicles]);

  const driverTripStats = useMemo(() => {
    const sources = new Map<string, { id: string; displayName: string }>();

    for (const driver of drivers) {
      const displayName = driver.name || driver.displayName || driver.emailAddress || driver.id;
      sources.set(normalizeText(displayName), {
        id: driver.id,
        displayName
      });
    }

    for (const member of members) {
      if (member.status === "removed") {
        continue;
      }
      const displayName = member.displayName || member.emailAddress;
      const key = normalizeText(displayName);
      if (!sources.has(key)) {
        sources.set(key, {
          id: member.id,
          displayName
        });
      }
    }

    for (const trip of trips) {
      const key = normalizeText(trip.driverName);
      if (!key || sources.has(key)) {
        continue;
      }
      sources.set(key, {
        id: key,
        displayName: trip.driverName || "Unknown driver"
      });
    }

    return Array.from(sources.entries()).map(([normalizedName, source]) => {
      const matchingTrips = trips.filter((trip) => normalizeText(trip.driverName) === normalizedName);
      const businessTrips = matchingTrips.filter((trip) => trip.tripType === "business");
      const distanceMeters = matchingTrips.reduce((totalDistance, trip) => totalDistance + (trip.distanceMeters ?? 0), 0);

      return {
        id: source.id,
        displayName: source.displayName,
        trips: matchingTrips.length,
        businessTrips: businessTrips.length,
        distanceMeters
      };
    });
  }, [drivers, members, trips]);

  async function handleCreateOrganization() {
    if (!uid || !emailAddress || !organizationName.trim()) {
      return;
    }

    setIsSaving(true);
    setStatus("");

    try {
      await createOrganizationForManager({
        uid,
        emailAddress,
        displayName: user?.displayName ?? emailAddress,
        organizationName,
        plan: organizationPlan
      });
      setStatus("Organization created. Sign out and back in if the membership card does not refresh immediately.");
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Unable to create organization.");
    } finally {
      setIsSaving(false);
    }
  }

  async function handleSaveMember() {
    if (!organizationContext?.organization.id || !memberForm.emailAddress.trim()) {
      return;
    }

    setIsSaving(true);
    setStatus("");

    try {
      await upsertCorporateInvite({
        memberID: memberForm.id,
        organizationID: organizationContext.organization.id,
        emailAddress: memberForm.emailAddress,
        displayName: memberForm.displayName,
        role: memberForm.role,
        assignedVehicleIDs: memberForm.assignedVehicleIDs,
        permissions: memberForm.permissions
      });

      setMembers(await fetchOrganizationMembers(organizationContext.organization.id));
      setMemberForm(emptyMemberForm);
      setStatus("Member saved and password setup email sent.");
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Unable to save member.");
    } finally {
      setIsSaving(false);
    }
  }

  async function handleRemoveMember(memberID: string) {
    if (!organizationContext?.organization.id) {
      return;
    }

    setIsSaving(true);
    setStatus("");

    try {
      await disableCorporateMember({
        organizationID: organizationContext.organization.id,
        memberID
      });
      setMembers(await fetchOrganizationMembers(organizationContext.organization.id));
      if (memberForm.id === memberID) {
        setMemberForm(emptyMemberForm);
      }
      setStatus("Member removed. Their access will be denied once Firestore rules are deployed.");
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Unable to remove member.");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <AuthGuard>
      <NavShell
        title="Organization"
        subtitle="Meerkat - Milage Tracker for Business: account setup, employees, vehicle assignments, and permissions."
      >
        {!organizationContext ? (
          <div className="card panel">
            <strong>Create Business Organization</strong>
            <p className="page-subtitle">
              This promotes the signed-in account into an account manager profile for a business subscription.
            </p>
            <div className="form-grid" style={{ marginTop: 16 }}>
              <label className="field">
                <span>Organization name</span>
                <input
                  className="input"
                  value={organizationName}
                  onChange={(event) => setOrganizationName(event.target.value)}
                />
              </label>
              <label className="field">
                <span>Plan</span>
                <select
                  className="input"
                  value={organizationPlan}
                  onChange={(event) => setOrganizationPlan(event.target.value as OrganizationPlan)}
                >
                  <option value="corporateMonthly">Business Monthly</option>
                  <option value="corporateYearly">Business Yearly</option>
                </select>
              </label>
              {status ? <div className="muted">{status}</div> : null}
              <button className="button" type="button" onClick={handleCreateOrganization} disabled={isSaving}>
                {isSaving ? "Creating…" : "Create Organization"}
              </button>
            </div>
          </div>
        ) : (
          <div className="grid" style={{ gridTemplateColumns: "minmax(0, 1.1fr) minmax(320px, 0.9fr)" }}>
            <div className="grid">
              <div className="card panel">
                <strong>{organizationContext.organization.name}</strong>
                <p className="page-subtitle">
                  Meerkat - Milage Tracker for Business • {organizationContext.organization.plan === "corporateYearly" ? "Business Yearly" : "Business Monthly"} • {isManager ? "Account Manager" : "Employee / Driver"}
                </p>
                <div className="muted" style={{ marginTop: 8 }}>
                  Billing: {labelForBillingStatus(organizationContext.organization.billingStatus)}
                  {organizationContext.organization.expiresAt?.seconds
                    ? ` • Access until ${new Date(organizationContext.organization.expiresAt.seconds * 1000).toLocaleDateString()}`
                    : ""}
                </div>
                {organizationContext.organization.billingStatus !== "active" && organizationContext.organization.billingStatus !== "trial" ? (
                  <div className="empty-state" style={{ marginTop: 14, textAlign: "left" }}>
                    Business access stays locked until payment is activated for this organization.
                  </div>
                ) : null}
                <div className="grid" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", marginTop: 14 }}>
                  <div>
                    <div className="muted">Members</div>
                    <div>{members.filter((entry) => entry.status !== "removed").length}</div>
                  </div>
                  <div>
                    <div className="muted">Assigned vehicles</div>
                    <div>{organizationContext.membership.assignedVehicleIDs?.length ?? 0}</div>
                  </div>
                  <div>
                    <div className="muted">Permissions</div>
                    <div>{organizationContext.membership.permissions?.length ?? (isManager ? allPermissions.length : 0)}</div>
                  </div>
                </div>
              </div>

              <div className="card panel">
                <strong>Business Data Explorer</strong>
                <p className="page-subtitle">
                  Filter by vehicle or driver/employee to review business account activity quickly.
                </p>

                <div className="grid" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", marginTop: 16 }}>
                  <label className="field">
                    <span>Vehicle filter</span>
                    <select
                      className="input"
                      value={selectedVehicleID}
                      onChange={(event) => setSelectedVehicleID(event.target.value)}
                    >
                      <option value="all">All vehicles</option>
                      {vehicles.map((vehicle) => (
                        <option key={vehicle.id} value={vehicle.id}>
                          {vehicle.displayName || vehicle.profileName || vehicle.id}
                        </option>
                      ))}
                    </select>
                  </label>

                  <label className="field">
                    <span>Driver / employee filter</span>
                    <select
                      className="input"
                      value={selectedDriverID}
                      onChange={(event) => setSelectedDriverID(event.target.value)}
                    >
                      <option value="all">All drivers / employees</option>
                      {driverFilterEntries.map((entry) => (
                        <option key={entry.id} value={entry.id}>
                          {entry.displayName}
                        </option>
                      ))}
                    </select>
                  </label>
                </div>

                <div className="grid stats" style={{ marginTop: 10 }}>
                  <div className="card panel">
                    <div className="muted">Trips (filtered)</div>
                    <p className="stat-value">{filteredTrips.length}</p>
                  </div>
                  <div className="card panel">
                    <div className="muted">Business Trips</div>
                    <p className="stat-value">{filteredTrips.filter((trip) => trip.tripType === "business").length}</p>
                  </div>
                  <div className="card panel">
                    <div className="muted">Distance (filtered)</div>
                    <p className="stat-value">
                      {formatDistance(filteredTrips.reduce((totalDistance, trip) => totalDistance + (trip.distanceMeters ?? 0), 0))} km
                    </p>
                  </div>
                </div>

                <div className="grid" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))", marginTop: 16 }}>
                  <div className="card panel" style={{ padding: 16 }}>
                    <strong>Vehicle Specific Data</strong>
                    <div className="grid" style={{ marginTop: 12 }}>
                      {vehicleTripStats.length === 0 ? (
                        <div className="empty-state">No vehicles available.</div>
                      ) : (
                        vehicleTripStats.map((entry) => (
                          <div key={entry.id} className="muted">
                            <span style={{ color: "var(--text)" }}>{entry.displayName}</span>
                            <div style={{ marginTop: 4 }}>
                              {entry.trips} trips • {entry.businessTrips} business • {formatDistance(entry.distanceMeters)} km
                            </div>
                          </div>
                        ))
                      )}
                    </div>
                  </div>

                  <div className="card panel" style={{ padding: 16 }}>
                    <strong>Driver / Employee Specific Data</strong>
                    <div className="grid" style={{ marginTop: 12 }}>
                      {driverTripStats.length === 0 ? (
                        <div className="empty-state">No drivers or employees available.</div>
                      ) : (
                        driverTripStats.map((entry) => (
                          <div key={entry.id} className="muted">
                            <span style={{ color: "var(--text)" }}>{entry.displayName}</span>
                            <div style={{ marginTop: 4 }}>
                              {entry.trips} trips • {entry.businessTrips} business • {formatDistance(entry.distanceMeters)} km
                            </div>
                          </div>
                        ))
                      )}
                    </div>
                  </div>
                </div>
              </div>

              <div className="card panel">
                <strong>Members</strong>
                <p className="page-subtitle">Managers can assign vehicles and granular permissions per employee.</p>
                <div className="grid" style={{ marginTop: 16 }}>
                  {members.length === 0 ? (
                    <div className="empty-state">No members added yet.</div>
                  ) : (
                    members.map((member) => (
                      <div key={member.id} className="card panel" style={{ padding: 16 }}>
                        <strong>{member.displayName || member.emailAddress}</strong>
                        <p className="page-subtitle">
                          {member.emailAddress} • {member.role === "accountManager" ? "Account Manager" : "Employee / Driver"} • {member.status}
                        </p>
                        <div className="muted" style={{ marginTop: 10 }}>
                          Vehicles: {member.assignedVehicleIDs?.length ? member.assignedVehicleIDs.map((vehicleID) => assignedVehicleNames.get(vehicleID) ?? vehicleID).join(", ") : "None"}
                        </div>
                        <div className="muted" style={{ marginTop: 6 }}>
                          Permissions: {member.role === "accountManager" ? "Full access" : (member.permissions ?? []).map(labelForPermission).join(", ") || "None"}
                        </div>
                        {isManager && member.id !== organizationContext.membership.id ? (
                          <div className="grid" style={{ gridTemplateColumns: "1fr 1fr", marginTop: 14 }}>
                            <button
                              className="button ghost"
                              type="button"
                              onClick={() =>
                                setMemberForm({
                                  id: member.id,
                                  emailAddress: member.emailAddress,
                                  displayName: member.displayName ?? "",
                                  role: member.role,
                                  assignedVehicleIDs: member.assignedVehicleIDs ?? [],
                                  permissions: member.permissions ?? []
                                })
                              }
                            >
                              Edit
                            </button>
                            <button
                              className="button"
                              type="button"
                              style={{ background: "#ae1f1f" }}
                              onClick={() => void handleRemoveMember(member.id)}
                              disabled={isSaving}
                            >
                              Remove
                            </button>
                          </div>
                        ) : null}
                      </div>
                    ))
                  )}
                </div>
              </div>
            </div>

            <div className="card panel">
              <strong>{memberForm.id ? "Edit Member" : "Invite Member"}</strong>
              <p className="page-subtitle">
                This stores membership, assignments, and permission controls for your business workspace.
              </p>

              <div className="form-grid" style={{ marginTop: 16 }}>
                <label className="field">
                  <span>Email</span>
                  <input
                    className="input"
                    value={memberForm.emailAddress}
                    onChange={(event) => setMemberForm({ ...memberForm, emailAddress: event.target.value })}
                    disabled={!isManager}
                  />
                </label>

                <label className="field">
                  <span>Name</span>
                  <input
                    className="input"
                    value={memberForm.displayName}
                    onChange={(event) => setMemberForm({ ...memberForm, displayName: event.target.value })}
                    disabled={!isManager}
                  />
                </label>

                <label className="field">
                  <span>Role</span>
                  <select
                    className="input"
                    value={memberForm.role}
                    onChange={(event) =>
                      setMemberForm({
                        ...memberForm,
                        role: event.target.value as MemberFormState["role"],
                        permissions:
                          event.target.value === "accountManager" ? allPermissions : memberForm.permissions
                      })
                    }
                    disabled={!isManager}
                  >
                    <option value="employee">Employee / Driver</option>
                    <option value="accountManager">Account Manager</option>
                  </select>
                </label>

                <label className="field">
                  <span>Assigned vehicles</span>
                  <select
                    className="input"
                    multiple
                    value={memberForm.assignedVehicleIDs}
                    onChange={(event) =>
                      setMemberForm({
                        ...memberForm,
                        assignedVehicleIDs: Array.from(event.target.selectedOptions, (option) => option.value)
                      })
                    }
                    disabled={!isManager}
                    style={{ minHeight: 140 }}
                  >
                    {vehicles.map((vehicle) => (
                      <option key={vehicle.id} value={vehicle.id}>
                        {vehicle.displayName || vehicle.profileName || vehicle.id}
                      </option>
                    ))}
                  </select>
                </label>

                <div className="field">
                  <span>Permissions</span>
                  <div className="grid" style={{ gap: 10 }}>
                    {allPermissions.map((permission) => (
                      <label key={permission} style={{ display: "flex", gap: 10, alignItems: "center" }}>
                        <input
                          type="checkbox"
                          checked={memberForm.role === "accountManager" || memberForm.permissions.includes(permission)}
                          disabled={!isManager || memberForm.role === "accountManager"}
                          onChange={(event) =>
                            setMemberForm((current) => ({
                              ...current,
                              permissions: event.target.checked
                                ? [...current.permissions, permission]
                                : current.permissions.filter((entry) => entry !== permission)
                            }))
                          }
                        />
                        <span>{labelForPermission(permission)}</span>
                      </label>
                    ))}
                  </div>
                </div>

                {status ? <div className="muted">{status}</div> : null}

                {isManager ? (
                  <div className="grid" style={{ gridTemplateColumns: "1fr 1fr" }}>
                    <button className="button" type="button" onClick={handleSaveMember} disabled={isSaving}>
                      {isSaving ? "Saving…" : memberForm.id ? "Update Member" : "Save Invite"}
                    </button>
                    <button
                      className="button ghost"
                      type="button"
                      onClick={() => {
                        setMemberForm(emptyMemberForm);
                        setStatus("");
                      }}
                      disabled={isSaving}
                    >
                      Clear
                    </button>
                  </div>
                ) : null}
              </div>
            </div>
          </div>
        )}
      </NavShell>
    </AuthGuard>
  );
}
