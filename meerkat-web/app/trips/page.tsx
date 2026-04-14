"use client";

import { useEffect, useState } from "react";
import { AuthGuard } from "@/components/auth-guard";
import { NavShell } from "@/components/nav-shell";
import { TripTable } from "@/components/trip-table";
import { useAuth } from "@/components/auth-provider";
import {
  deleteTrip,
  fetchScopedCollection,
  fetchUserProfile,
  saveTrip,
  TripRecord,
  TripUpdateInput,
  UserProfile
} from "@/lib/firestore";

type TripFormState = {
  id: string;
  ownerUID?: string;
  name: string;
  tripType: string;
  vehicleProfileName: string;
  driverName: string;
  startAddress: string;
  endAddress: string;
  details: string;
  odometerStart: string;
  odometerEnd: string;
  distanceMeters: string;
  date: string;
};

function toInputDate(value?: { seconds: number }) {
  if (!value?.seconds) {
    return "";
  }

  return new Date(value.seconds * 1000).toISOString().slice(0, 10);
}

function distanceUnitLabel(unitSystem?: string) {
  return unitSystem === "miles" ? "Miles" : "KM";
}

function toDisplayDistance(distanceMeters: number | undefined, unitSystem?: string) {
  const safeDistance = distanceMeters ?? 0;

  if (unitSystem === "miles") {
    return safeDistance / 1609.344;
  }

  return safeDistance / 1000;
}

function toStoredDistance(distanceValue: string, unitSystem?: string) {
  const parsedValue = Number(distanceValue) || 0;

  if (unitSystem === "miles") {
    return parsedValue * 1609.344;
  }

  return parsedValue * 1000;
}

function sortTripsNewestFirst(records: TripRecord[]) {
  return [...records].sort((lhs, rhs) => {
    const lhsDate = lhs.date?.seconds ?? 0;
    const rhsDate = rhs.date?.seconds ?? 0;
    return rhsDate - lhsDate;
  });
}

function toFormState(trip: TripRecord, unitSystem?: string): TripFormState {
  return {
    id: trip.id,
    ownerUID: trip.ownerUID,
    name: trip.name ?? "",
    tripType: trip.tripType ?? "business",
    vehicleProfileName: trip.vehicleProfileName ?? "",
    driverName: trip.driverName ?? "",
    startAddress: trip.startAddress ?? "",
    endAddress: trip.endAddress ?? "",
    details: trip.details ?? "",
    odometerStart: String(trip.odometerStart ?? 0),
    odometerEnd: String(trip.odometerEnd ?? 0),
    distanceMeters: String(toDisplayDistance(trip.distanceMeters, unitSystem)),
    date: toInputDate(trip.date)
  };
}

export default function TripsPage() {
  const { user, organizationContext } = useAuth();
  const uid = user?.uid;
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [trips, setTrips] = useState<TripRecord[]>([]);
  const [selectedTripID, setSelectedTripID] = useState("");
  const [selectedTripIDs, setSelectedTripIDs] = useState<string[]>([]);
  const [formState, setFormState] = useState<TripFormState | null>(null);
  const [status, setStatus] = useState("");
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    if (!uid) {
      return;
    }
    const safeUID = uid;

    async function loadTrips() {
      const nextProfile = await fetchUserProfile(safeUID);
      const nextTrips = sortTripsNewestFirst(
        await fetchScopedCollection<TripRecord>(safeUID, organizationContext, "trips")
      );
      setProfile(nextProfile);
      setTrips(nextTrips);
      setSelectedTripIDs((currentSelectedTripIDs) =>
        currentSelectedTripIDs.filter((tripID) => nextTrips.some((trip) => trip.id == tripID))
      );

      if (nextTrips.length > 0 && !selectedTripID) {
        setSelectedTripID(nextTrips[0].id);
        setFormState(toFormState(nextTrips[0], nextProfile?.unitSystem));
      }
    }

    void loadTrips();
  }, [organizationContext, selectedTripID, uid]);

  useEffect(() => {
    if (!selectedTripID) {
      return;
    }

    const selectedTrip = trips.find((entry) => entry.id === selectedTripID);
    if (selectedTrip) {
      setFormState(toFormState(selectedTrip, profile?.unitSystem));
      setStatus("");
    }
  }, [profile?.unitSystem, selectedTripID, trips]);

  async function handleSave() {
    if (!uid || !formState) {
      return;
    }
    const safeUID = uid;

    setSaving(true);
    setStatus("");

    try {
      const payload: TripUpdateInput = {
        id: formState.id,
        name: formState.name,
        tripType: formState.tripType,
        vehicleProfileName: formState.vehicleProfileName,
        driverName: formState.driverName,
        startAddress: formState.startAddress,
        endAddress: formState.endAddress,
        details: formState.details,
        odometerStart: Number(formState.odometerStart) || 0,
        odometerEnd: Number(formState.odometerEnd) || 0,
        distanceMeters: toStoredDistance(formState.distanceMeters, profile?.unitSystem),
        date: formState.date ? new Date(formState.date) : new Date()
      };

      await saveTrip(formState.ownerUID || safeUID, payload);
      setTrips((currentTrips) =>
        sortTripsNewestFirst(
          currentTrips.map((trip) =>
            trip.id === payload.id
              ? {
                  ...trip,
                  ...payload,
                  date: { seconds: Math.floor(payload.date.getTime() / 1000) }
                }
              : trip
          )
        )
      );
      setStatus("Trip saved to Firebase.");
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Unable to save trip.");
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete() {
    if (!uid || !formState) {
      return;
    }
    const safeUID = uid;

    if (!window.confirm("Delete this trip from Firebase? This cannot be undone.")) {
      return;
    }

    setDeleting(true);
    setStatus("");

    try {
      await deleteTrip(formState.ownerUID || safeUID, formState.id);

      setTrips((currentTrips) => {
        const nextTrips = currentTrips.filter((trip) => trip.id !== formState.id);
        const nextSelectedTrip = nextTrips[0];
        setSelectedTripID(nextSelectedTrip?.id ?? "");
        setFormState(nextSelectedTrip ? toFormState(nextSelectedTrip) : null);
        return nextTrips;
      });
      setStatus("Trip deleted from Firebase.");
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Unable to delete trip.");
    } finally {
      setDeleting(false);
    }
  }

  async function handleDeleteSelected() {
    if (!uid || selectedTripIDs.length == 0) {
      return;
    }
    const safeUID = uid;
    const tripIDsToDelete = selectedTripIDs;

    if (!window.confirm(`Delete ${tripIDsToDelete.length} selected trips from Firebase? This cannot be undone.`)) {
      return;
    }

    setDeleting(true);
    setStatus("");

    try {
      await Promise.all(
        tripIDsToDelete.map((tripID) => {
          const record = trips.find((trip) => trip.id === tripID);
          return deleteTrip(record?.ownerUID || safeUID, tripID);
        })
      );

      setTrips((currentTrips) => {
        const nextTrips = currentTrips.filter((trip) => !tripIDsToDelete.includes(trip.id));
        const didDeleteCurrentTrip = formState ? tripIDsToDelete.includes(formState.id) : false;
        let nextSelectedTripID = selectedTripID;
        let nextFormState = formState;

        if (didDeleteCurrentTrip) {
          let nextSelectedTrip = nextTrips[0];
          if (selectedTripID) {
            nextSelectedTrip = nextTrips.find((trip) => trip.id === selectedTripID) ?? nextSelectedTrip;
          }
          nextSelectedTripID = nextSelectedTrip?.id ?? "";
          nextFormState = nextSelectedTrip ? toFormState(nextSelectedTrip, profile?.unitSystem) : null;
        }

        setSelectedTripID(nextSelectedTripID);
        setFormState(nextFormState);
        return nextTrips;
      });
      setSelectedTripIDs([]);
      setStatus(`${tripIDsToDelete.length} trips deleted from Firebase.`);
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Unable to delete selected trips.");
    } finally {
      setDeleting(false);
    }
  }

  function toggleTripSelection(tripID: string) {
    setSelectedTripIDs((currentSelectedTripIDs) => {
      if (currentSelectedTripIDs.includes(tripID)) {
        return currentSelectedTripIDs.filter((currentTripID) => currentTripID !== tripID);
      }

      return [...currentSelectedTripIDs, tripID];
    });
  }

  return (
    <AuthGuard>
      <NavShell
        title="Trips"
        subtitle={organizationContext?.membership.role === "accountManager"
          ? "Browse and edit trips across active employees in this organization."
          : "Browse synced mileage trips and edit the core fields directly from the web portal."}
      >
        <div className="grid" style={{ gridTemplateColumns: "minmax(0, 1.2fr) minmax(320px, 0.8fr)" }}>
          <div style={{ maxHeight: "calc(100vh - 220px)", overflowY: "auto" }}>
            <div className="card panel" style={{ marginBottom: 12 }}>
              <div className="grid" style={{ gridTemplateColumns: "1fr auto auto", alignItems: "center" }}>
                <div className="muted">
                  {selectedTripIDs.length == 0
                    ? "Select one or more trips to bulk delete them."
                    : `${selectedTripIDs.length} trip${selectedTripIDs.length == 1 ? "" : "s"} selected`}
                </div>

                <button
                  className="button secondary"
                  type="button"
                  onClick={() => setSelectedTripIDs(trips.map((trip) => trip.id))}
                  disabled={trips.length == 0 || deleting}
                >
                  Select All
                </button>

                <button
                  className="button"
                  type="button"
                  onClick={handleDeleteSelected}
                  disabled={selectedTripIDs.length == 0 || saving || deleting}
                  style={{
                    background: deleting ? "rgba(174, 31, 31, 0.75)" : "#ae1f1f"
                  }}
                >
                  {deleting ? "Deleting…" : "Delete Selected"}
                </button>
              </div>
            </div>

            <TripTable
              trips={trips}
              selectedTripID={selectedTripID}
              onSelectTrip={(trip) => setSelectedTripID(trip.id)}
              unitSystem={profile?.unitSystem}
              selectedTripIDs={selectedTripIDs}
              onToggleTripSelection={toggleTripSelection}
            />
          </div>

          <div className="card panel" style={{ position: "sticky", top: 24, alignSelf: "start" }}>
            <strong>Edit Trip</strong>
            <p className="page-subtitle">
              {organizationContext?.membership.role === "accountManager"
                ? "Save changes back to the employee account that owns this trip."
                : "Save changes back to Firestore for this account."}
            </p>

            <div className="form-grid" style={{ marginTop: 16 }}>
              <label className="field">
                <span>Select trip</span>
                <select
                  className="input"
                  value={selectedTripID}
                  onChange={(event) => setSelectedTripID(event.target.value)}
                >
                  {trips.map((trip) => (
                    <option key={trip.id} value={trip.id}>
                      {(trip.name || trip.tripType || "Trip") + " • " + (trip.vehicleProfileName || "Unknown vehicle")}
                    </option>
                  ))}
                </select>
              </label>

              {formState ? (
                <>
                  <label className="field">
                    <span>Trip name</span>
                    <input
                      className="input"
                      value={formState.name}
                      onChange={(event) =>
                        setFormState({ ...formState, name: event.target.value })
                      }
                    />
                  </label>

                  <label className="field">
                    <span>Trip type</span>
                    <select
                      className="input"
                      value={formState.tripType}
                      onChange={(event) =>
                        setFormState({ ...formState, tripType: event.target.value })
                      }
                    >
                      <option value="business">Business</option>
                      <option value="personal">Personal</option>
                    </select>
                  </label>

                  <label className="field">
                    <span>Vehicle</span>
                    <input
                      className="input"
                      value={formState.vehicleProfileName}
                      onChange={(event) =>
                        setFormState({ ...formState, vehicleProfileName: event.target.value })
                      }
                    />
                  </label>

                  <label className="field">
                    <span>Driver</span>
                    <input
                      className="input"
                      value={formState.driverName}
                      onChange={(event) =>
                        setFormState({ ...formState, driverName: event.target.value })
                      }
                    />
                  </label>

                  <label className="field">
                    <span>Date</span>
                    <input
                      className="input"
                      type="date"
                      value={formState.date}
                      onChange={(event) =>
                        setFormState({ ...formState, date: event.target.value })
                      }
                    />
                  </label>

                  <label className="field">
                    <span>Start address</span>
                    <input
                      className="input"
                      value={formState.startAddress}
                      onChange={(event) =>
                        setFormState({ ...formState, startAddress: event.target.value })
                      }
                    />
                  </label>

                  <label className="field">
                    <span>End address</span>
                    <input
                      className="input"
                      value={formState.endAddress}
                      onChange={(event) =>
                        setFormState({ ...formState, endAddress: event.target.value })
                      }
                    />
                  </label>

                  <label className="field">
                    <span>Details</span>
                    <textarea
                      className="textarea"
                      rows={4}
                      value={formState.details}
                      onChange={(event) =>
                        setFormState({ ...formState, details: event.target.value })
                      }
                    />
                  </label>

                  <div className="grid" style={{ gridTemplateColumns: "repeat(3, minmax(0, 1fr))" }}>
                    <label className="field">
                      <span>Start odometer</span>
                      <input
                        className="input"
                        inputMode="decimal"
                        value={formState.odometerStart}
                        onChange={(event) =>
                          setFormState({ ...formState, odometerStart: event.target.value })
                        }
                      />
                    </label>

                    <label className="field">
                      <span>End odometer</span>
                      <input
                        className="input"
                        inputMode="decimal"
                        value={formState.odometerEnd}
                        onChange={(event) =>
                          setFormState({ ...formState, odometerEnd: event.target.value })
                        }
                      />
                    </label>

                    <label className="field">
                      <span>Distance {distanceUnitLabel(profile?.unitSystem)}</span>
                      <input
                        className="input"
                        inputMode="decimal"
                        value={formState.distanceMeters}
                        onChange={(event) =>
                          setFormState({ ...formState, distanceMeters: event.target.value })
                        }
                      />
                    </label>
                  </div>

                  {status ? <div className="muted">{status}</div> : null}

                  <div className="grid" style={{ gridTemplateColumns: "1fr 1fr" }}>
                    <button className="button" type="button" onClick={handleSave} disabled={saving || deleting}>
                      {saving ? "Saving…" : "Save Trip"}
                    </button>

                    <button
                      className="button"
                      type="button"
                      onClick={handleDelete}
                      disabled={saving || deleting}
                      style={{
                        background: deleting ? "rgba(174, 31, 31, 0.75)" : "#ae1f1f"
                      }}
                    >
                      {deleting ? "Deleting…" : "Delete Trip"}
                    </button>
                  </div>
                </>
              ) : (
                <div className="empty-state">No trip selected.</div>
              )}
            </div>
          </div>
        </div>
      </NavShell>
    </AuthGuard>
  );
}
