"use client";

import { useEffect, useState } from "react";
import { AuthGuard } from "@/components/auth-guard";
import { NavShell } from "@/components/nav-shell";
import { useAuth } from "@/components/auth-provider";
import {
  fetchCollectionUnordered,
  saveVehicle,
  VehicleRecord,
  VehicleUpdateInput
} from "@/lib/firestore";

type VehicleFormState = {
  id: string;
  profileName: string;
  make: string;
  model: string;
  color: string;
  numberPlate: string;
  startingOdometerReading: string;
  archived: boolean;
};

function toFormState(vehicle: VehicleRecord): VehicleFormState {
  return {
    id: vehicle.id,
    profileName: vehicle.profileName ?? vehicle.displayName ?? "",
    make: vehicle.make ?? "",
    model: vehicle.model ?? "",
    color: "",
    numberPlate: vehicle.numberPlate ?? "",
    startingOdometerReading: String(vehicle.startingOdometerReading ?? 0),
    archived: Boolean(vehicle.archived)
  };
}

export default function VehiclesPage() {
  const { user } = useAuth();
  const uid = user?.uid;
  const [vehicles, setVehicles] = useState<VehicleRecord[]>([]);
  const [selectedVehicleID, setSelectedVehicleID] = useState("");
  const [formState, setFormState] = useState<VehicleFormState | null>(null);
  const [status, setStatus] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!uid) {
      return;
    }

    async function loadVehicles() {
      const nextVehicles = await fetchCollectionUnordered<VehicleRecord>(uid, "vehicles");
      setVehicles(nextVehicles);

      if (nextVehicles.length > 0 && !selectedVehicleID) {
        setSelectedVehicleID(nextVehicles[0].id);
        setFormState(toFormState(nextVehicles[0]));
      }
    }

    void loadVehicles();
  }, [selectedVehicleID, uid]);

  useEffect(() => {
    if (!selectedVehicleID) {
      return;
    }

    const selectedVehicle = vehicles.find((entry) => entry.id === selectedVehicleID);
    if (selectedVehicle) {
      setFormState(toFormState(selectedVehicle));
      setStatus("");
    }
  }, [selectedVehicleID, vehicles]);

  async function handleSave() {
    if (!uid || !formState) {
      return;
    }

    setSaving(true);
    setStatus("");

    try {
      const payload: VehicleUpdateInput = {
        id: formState.id,
        profileName: formState.profileName,
        make: formState.make,
        model: formState.model,
        color: formState.color,
        numberPlate: formState.numberPlate,
        startingOdometerReading: Number(formState.startingOdometerReading) || 0,
        archived: formState.archived
      };

      await saveVehicle(uid, payload);
      setVehicles((currentVehicles) =>
        currentVehicles.map((vehicle) =>
          vehicle.id === payload.id
            ? {
                ...vehicle,
                profileName: payload.profileName,
                displayName: payload.profileName || [payload.make, payload.model].filter(Boolean).join(" "),
                make: payload.make,
                model: payload.model,
                numberPlate: payload.numberPlate,
                startingOdometerReading: payload.startingOdometerReading,
                archived: payload.archived
              }
            : vehicle
        )
      );
      setStatus("Vehicle saved to Firebase.");
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Unable to save vehicle.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <AuthGuard>
      <NavShell
        title="Vehicles"
        subtitle="Vehicle profiles synced from the mobile app and editable on the web."
      >
        <div className="grid" style={{ gridTemplateColumns: "minmax(0, 1fr) minmax(320px, 0.9fr)" }}>
          <div className="grid">
            {vehicles.length === 0 ? (
              <div className="empty-state">No vehicles found for this account.</div>
            ) : (
              vehicles.map((vehicle) => (
                <button
                  key={vehicle.id}
                  type="button"
                  className="card panel"
                  style={{
                    textAlign: "left",
                    cursor: "pointer",
                    outline: vehicle.id === selectedVehicleID ? "2px solid var(--brand)" : "none"
                  }}
                  onClick={() => setSelectedVehicleID(vehicle.id)}
                >
                  <strong>{vehicle.displayName || vehicle.profileName || "Vehicle"}</strong>
                  <p className="page-subtitle">
                    {[vehicle.make, vehicle.model].filter(Boolean).join(" ")} • {vehicle.numberPlate || "No plate"}
                  </p>
                  <div style={{ marginTop: 12 }}>
                    Starting odometer: {vehicle.startingOdometerReading ?? "—"}
                  </div>
                  <div className="muted" style={{ marginTop: 8 }}>
                    {vehicle.archived ? "Archived" : "Active"}
                  </div>
                </button>
              ))
            )}
          </div>

          <div className="card panel">
            <strong>Edit Vehicle</strong>
            <p className="page-subtitle">Update the customer-facing vehicle profile.</p>

            <div className="form-grid" style={{ marginTop: 16 }}>
              <label className="field">
                <span>Select vehicle</span>
                <select
                  className="input"
                  value={selectedVehicleID}
                  onChange={(event) => setSelectedVehicleID(event.target.value)}
                >
                  {vehicles.map((vehicle) => (
                    <option key={vehicle.id} value={vehicle.id}>
                      {vehicle.displayName || vehicle.profileName || "Vehicle"}
                    </option>
                  ))}
                </select>
              </label>

              {formState ? (
                <>
                  <label className="field">
                    <span>Profile name</span>
                    <input
                      className="input"
                      value={formState.profileName}
                      onChange={(event) =>
                        setFormState({ ...formState, profileName: event.target.value })
                      }
                    />
                  </label>

                  <div className="grid" style={{ gridTemplateColumns: "repeat(2, minmax(0, 1fr))" }}>
                    <label className="field">
                      <span>Make</span>
                      <input
                        className="input"
                        value={formState.make}
                        onChange={(event) =>
                          setFormState({ ...formState, make: event.target.value })
                        }
                      />
                    </label>

                    <label className="field">
                      <span>Model</span>
                      <input
                        className="input"
                        value={formState.model}
                        onChange={(event) =>
                          setFormState({ ...formState, model: event.target.value })
                        }
                      />
                    </label>
                  </div>

                  <div className="grid" style={{ gridTemplateColumns: "repeat(2, minmax(0, 1fr))" }}>
                    <label className="field">
                      <span>Color</span>
                      <input
                        className="input"
                        value={formState.color}
                        onChange={(event) =>
                          setFormState({ ...formState, color: event.target.value })
                        }
                      />
                    </label>

                    <label className="field">
                      <span>Plate</span>
                      <input
                        className="input"
                        value={formState.numberPlate}
                        onChange={(event) =>
                          setFormState({ ...formState, numberPlate: event.target.value })
                        }
                      />
                    </label>
                  </div>

                  <label className="field">
                    <span>Starting odometer</span>
                    <input
                      className="input"
                      inputMode="decimal"
                      value={formState.startingOdometerReading}
                      onChange={(event) =>
                        setFormState({
                          ...formState,
                          startingOdometerReading: event.target.value
                        })
                      }
                    />
                  </label>

                  <label style={{ display: "flex", alignItems: "center", gap: 10 }}>
                    <input
                      type="checkbox"
                      checked={formState.archived}
                      onChange={(event) =>
                        setFormState({ ...formState, archived: event.target.checked })
                      }
                    />
                    Archived
                  </label>

                  {status ? <div className="muted">{status}</div> : null}

                  <button className="button" type="button" onClick={handleSave} disabled={saving}>
                    {saving ? "Saving…" : "Save Vehicle"}
                  </button>
                </>
              ) : (
                <div className="empty-state">No vehicle selected.</div>
              )}
            </div>
          </div>
        </div>
      </NavShell>
    </AuthGuard>
  );
}
