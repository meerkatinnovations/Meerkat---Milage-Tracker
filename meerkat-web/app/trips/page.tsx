"use client";

import { useEffect, useState } from "react";
import { AuthGuard } from "@/components/auth-guard";
import { NavShell } from "@/components/nav-shell";
import { TripTable } from "@/components/trip-table";
import { useAuth } from "@/components/auth-provider";
import {
  fetchCollection,
  saveTrip,
  TripRecord,
  TripUpdateInput
} from "@/lib/firestore";

type TripFormState = {
  id: string;
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

function toFormState(trip: TripRecord): TripFormState {
  return {
    id: trip.id,
    name: trip.name ?? "",
    tripType: trip.tripType ?? "business",
    vehicleProfileName: trip.vehicleProfileName ?? "",
    driverName: trip.driverName ?? "",
    startAddress: trip.startAddress ?? "",
    endAddress: trip.endAddress ?? "",
    details: trip.details ?? "",
    odometerStart: String(trip.odometerStart ?? 0),
    odometerEnd: String(trip.odometerEnd ?? 0),
    distanceMeters: String(trip.distanceMeters ?? 0),
    date: toInputDate(trip.date)
  };
}

export default function TripsPage() {
  const { user } = useAuth();
  const uid = user?.uid;
  const [trips, setTrips] = useState<TripRecord[]>([]);
  const [selectedTripID, setSelectedTripID] = useState("");
  const [formState, setFormState] = useState<TripFormState | null>(null);
  const [status, setStatus] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!uid) {
      return;
    }

    async function loadTrips() {
      const nextTrips = await fetchCollection<TripRecord>(uid, "trips");
      setTrips(nextTrips);

      if (nextTrips.length > 0 && !selectedTripID) {
        setSelectedTripID(nextTrips[0].id);
        setFormState(toFormState(nextTrips[0]));
      }
    }

    void loadTrips();
  }, [selectedTripID, uid]);

  useEffect(() => {
    if (!selectedTripID) {
      return;
    }

    const selectedTrip = trips.find((entry) => entry.id === selectedTripID);
    if (selectedTrip) {
      setFormState(toFormState(selectedTrip));
      setStatus("");
    }
  }, [selectedTripID, trips]);

  async function handleSave() {
    if (!uid || !formState) {
      return;
    }

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
        distanceMeters: Number(formState.distanceMeters) || 0,
        date: formState.date ? new Date(formState.date) : new Date()
      };

      await saveTrip(uid, payload);
      setTrips((currentTrips) =>
        currentTrips.map((trip) =>
          trip.id === payload.id
            ? {
                ...trip,
                ...payload,
                date: { seconds: Math.floor(payload.date.getTime() / 1000) }
              }
            : trip
        )
      );
      setStatus("Trip saved to Firebase.");
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Unable to save trip.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <AuthGuard>
      <NavShell
        title="Trips"
        subtitle="Browse synced mileage trips and edit the core fields directly from the web portal."
      >
        <div className="grid" style={{ gridTemplateColumns: "minmax(0, 1.2fr) minmax(320px, 0.8fr)" }}>
          <TripTable trips={trips} />

          <div className="card panel">
            <strong>Edit Trip</strong>
            <p className="page-subtitle">Save changes back to Firestore for this account.</p>

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
                      <span>Distance meters</span>
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

                  <button className="button" type="button" onClick={handleSave} disabled={saving}>
                    {saving ? "Saving…" : "Save Trip"}
                  </button>
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
