"use client";

import { useEffect, useState } from "react";
import { AuthGuard } from "@/components/auth-guard";
import { NavShell } from "@/components/nav-shell";
import { useAuth } from "@/components/auth-provider";
import {
  fetchCollection,
  fetchUserProfile,
  FuelRecord,
  FuelUpdateInput,
  saveFuelEntry,
  UserProfile
} from "@/lib/firestore";

type FuelFormState = {
  id: string;
  station: string;
  vehicleProfileName: string;
  volume: string;
  totalCost: string;
  odometer: string;
};

function toFormState(entry: FuelRecord): FuelFormState {
  return {
    id: entry.id,
    station: entry.station ?? "",
    vehicleProfileName: entry.vehicleProfileName ?? "",
    volume: String(entry.volume ?? 0),
    totalCost: String(entry.totalCost ?? 0),
    odometer: String(entry.odometer ?? 0)
  };
}

export default function FuelPage() {
  const { user } = useAuth();
  const uid = user?.uid;
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [entries, setEntries] = useState<FuelRecord[]>([]);
  const [selectedEntryID, setSelectedEntryID] = useState("");
  const [formState, setFormState] = useState<FuelFormState | null>(null);
  const [status, setStatus] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!uid) {
      return;
    }
    const safeUID = uid;

    async function loadEntries() {
      const nextProfile = await fetchUserProfile(safeUID);
      const nextEntries = await fetchCollection<FuelRecord>(safeUID, "fuelEntries");
      setProfile(nextProfile);
      setEntries(nextEntries);

      if (nextEntries.length > 0 && !selectedEntryID) {
        setSelectedEntryID(nextEntries[0].id);
        setFormState(toFormState(nextEntries[0]));
      }
    }

    void loadEntries();
  }, [selectedEntryID, uid]);

  useEffect(() => {
    if (!selectedEntryID) {
      return;
    }

    const selectedEntry = entries.find((entry) => entry.id === selectedEntryID);
    if (selectedEntry) {
      setFormState(toFormState(selectedEntry));
      setStatus("");
    }
  }, [entries, selectedEntryID]);

  async function handleSave() {
    if (!uid || !formState) {
      return;
    }
    const safeUID = uid;

    setSaving(true);
    setStatus("");

    try {
      const payload: FuelUpdateInput = {
        id: formState.id,
        station: formState.station,
        vehicleProfileName: formState.vehicleProfileName,
        volume: Number(formState.volume) || 0,
        totalCost: Number(formState.totalCost) || 0,
        odometer: Number(formState.odometer) || 0
      };

      await saveFuelEntry(safeUID, payload);
      setEntries((currentEntries) =>
        currentEntries.map((entry) =>
          entry.id === payload.id
            ? {
                ...entry,
                station: payload.station,
                vehicleProfileName: payload.vehicleProfileName,
                volume: payload.volume,
                totalCost: payload.totalCost,
                odometer: payload.odometer
              }
            : entry
        )
      );
      setStatus("Fuel entry saved to Firebase.");
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Unable to save fuel entry.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <AuthGuard>
      <NavShell
        title="Fuel"
        subtitle="Fuel purchase records and receipt storage references."
      >
        <div className="grid" style={{ gridTemplateColumns: "minmax(0, 1fr) minmax(320px, 0.9fr)" }}>
          <div className="card panel table-wrap" style={{ maxHeight: "calc(100vh - 220px)", overflowY: "auto" }}>
            <table>
              <thead>
                <tr>
                  <th>Station</th>
                  <th>Vehicle</th>
                  <th>Volume</th>
                  <th>Cost</th>
                  <th>Odometer</th>
                  <th>Receipt</th>
                </tr>
              </thead>
              <tbody>
                {entries.map((entry) => (
                  <tr
                    key={entry.id}
                    onClick={() => setSelectedEntryID(entry.id)}
                    style={{
                      cursor: "pointer",
                      background: entry.id === selectedEntryID ? "rgba(31, 122, 90, 0.08)" : "transparent"
                    }}
                  >
                    <td>{entry.station || "—"}</td>
                    <td>{entry.vehicleProfileName || "—"}</td>
                    <td>{entry.volume ?? "—"}</td>
                    <td>{entry.totalCost ?? "—"}</td>
                    <td>{entry.odometer ?? "—"} {profile?.unitSystem === "miles" ? "mi" : "km"}</td>
                    <td>{entry.receiptPath ? "Stored" : "None"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="card panel" style={{ position: "sticky", top: 24, alignSelf: "start" }}>
            <strong>Edit Fuel Entry</strong>
            <p className="page-subtitle">Update station, cost, volume, and odometer.</p>

            <div className="form-grid" style={{ marginTop: 16 }}>
              <label className="field">
                <span>Select fuel entry</span>
                <select
                  className="input"
                  value={selectedEntryID}
                  onChange={(event) => setSelectedEntryID(event.target.value)}
                >
                  {entries.map((entry) => (
                    <option key={entry.id} value={entry.id}>
                      {(entry.station || "Fuel entry") + " • " + (entry.vehicleProfileName || "Unknown vehicle")}
                    </option>
                  ))}
                </select>
              </label>

              {formState ? (
                <>
                  <label className="field">
                    <span>Station</span>
                    <input
                      className="input"
                      value={formState.station}
                      onChange={(event) => setFormState({ ...formState, station: event.target.value })}
                    />
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

                  <div className="grid" style={{ gridTemplateColumns: "repeat(3, minmax(0, 1fr))" }}>
                    <label className="field">
                      <span>Volume</span>
                      <input
                        className="input"
                        inputMode="decimal"
                        value={formState.volume}
                        onChange={(event) => setFormState({ ...formState, volume: event.target.value })}
                      />
                    </label>

                    <label className="field">
                      <span>Total cost</span>
                      <input
                        className="input"
                        inputMode="decimal"
                        value={formState.totalCost}
                        onChange={(event) =>
                          setFormState({ ...formState, totalCost: event.target.value })
                        }
                      />
                    </label>

                    <label className="field">
                      <span>Odometer {profile?.unitSystem === "miles" ? "(mi)" : "(km)"}</span>
                      <input
                        className="input"
                        inputMode="decimal"
                        value={formState.odometer}
                        onChange={(event) => setFormState({ ...formState, odometer: event.target.value })}
                      />
                    </label>
                  </div>

                  {status ? <div className="muted">{status}</div> : null}

                  <button className="button" type="button" onClick={handleSave} disabled={saving}>
                    {saving ? "Saving…" : "Save Fuel Entry"}
                  </button>
                </>
              ) : (
                <div className="empty-state">No fuel entry selected.</div>
              )}
            </div>
          </div>
        </div>
      </NavShell>
    </AuthGuard>
  );
}
