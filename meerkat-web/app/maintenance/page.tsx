"use client";

import { useEffect, useState } from "react";
import { AuthGuard } from "@/components/auth-guard";
import { NavShell } from "@/components/nav-shell";
import { useAuth } from "@/components/auth-provider";
import {
  fetchCollectionUnordered,
  MaintenanceRecord,
  MaintenanceUpdateInput,
  saveMaintenanceRecord
} from "@/lib/firestore";

type MaintenanceFormState = {
  id: string;
  shopName: string;
  vehicleProfileName: string;
  type: string;
  otherDescription: string;
  notes: string;
  totalCost: string;
  odometer: string;
  reminderEnabled: boolean;
  nextServiceOdometer: string;
};

function toFormState(record: MaintenanceRecord): MaintenanceFormState {
  return {
    id: record.id,
    shopName: record.shopName ?? "",
    vehicleProfileName: record.vehicleProfileName ?? "",
    type: record.type ?? "Oil Change",
    otherDescription: record.otherDescription ?? "",
    notes: record.notes ?? "",
    totalCost: String(record.totalCost ?? 0),
    odometer: String(record.odometer ?? 0),
    reminderEnabled: Boolean(record.reminderEnabled),
    nextServiceOdometer: String(record.nextServiceOdometer ?? 0)
  };
}

export default function MaintenancePage() {
  const { user } = useAuth();
  const [records, setRecords] = useState<MaintenanceRecord[]>([]);
  const [selectedRecordID, setSelectedRecordID] = useState("");
  const [formState, setFormState] = useState<MaintenanceFormState | null>(null);
  const [status, setStatus] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!user) {
      return;
    }

    async function loadRecords() {
      const nextRecords = await fetchCollectionUnordered<MaintenanceRecord>(user.uid, "maintenanceRecords");
      setRecords(nextRecords);

      if (nextRecords.length > 0 && !selectedRecordID) {
        setSelectedRecordID(nextRecords[0].id);
        setFormState(toFormState(nextRecords[0]));
      }
    }

    void loadRecords();
  }, [selectedRecordID, user]);

  useEffect(() => {
    if (!selectedRecordID) {
      return;
    }

    const selectedRecord = records.find((entry) => entry.id === selectedRecordID);
    if (selectedRecord) {
      setFormState(toFormState(selectedRecord));
      setStatus("");
    }
  }, [records, selectedRecordID]);

  async function handleSave() {
    if (!user || !formState) {
      return;
    }

    setSaving(true);
    setStatus("");

    try {
      const payload: MaintenanceUpdateInput = {
        id: formState.id,
        shopName: formState.shopName,
        vehicleProfileName: formState.vehicleProfileName,
        type: formState.type,
        otherDescription: formState.otherDescription,
        notes: formState.notes,
        totalCost: Number(formState.totalCost) || 0,
        odometer: Number(formState.odometer) || 0,
        reminderEnabled: formState.reminderEnabled,
        nextServiceOdometer: formState.nextServiceOdometer
          ? Number(formState.nextServiceOdometer)
          : undefined
      };

      await saveMaintenanceRecord(user.uid, payload);
      setRecords((currentRecords) =>
        currentRecords.map((record) =>
          record.id === payload.id
            ? {
                ...record,
                shopName: payload.shopName,
                vehicleProfileName: payload.vehicleProfileName,
                type: payload.type,
                otherDescription: payload.otherDescription,
                notes: payload.notes,
                totalCost: payload.totalCost,
                odometer: payload.odometer,
                reminderEnabled: payload.reminderEnabled,
                nextServiceOdometer: payload.nextServiceOdometer
              }
            : record
        )
      );
      setStatus("Maintenance record saved to Firebase.");
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Unable to save maintenance record.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <AuthGuard>
      <NavShell
        title="Maintenance"
        subtitle="Service history synced from Meerkat and editable from the customer portal."
      >
        <div className="grid" style={{ gridTemplateColumns: "minmax(0, 1fr) minmax(320px, 0.9fr)" }}>
          <div className="grid">
            {records.length === 0 ? (
              <div className="empty-state">No maintenance records are synced yet.</div>
            ) : (
              records.map((record) => (
                <button
                  type="button"
                  className="card panel"
                  key={record.id}
                  style={{
                    textAlign: "left",
                    cursor: "pointer",
                    outline: record.id === selectedRecordID ? "2px solid var(--brand)" : "none"
                  }}
                  onClick={() => setSelectedRecordID(record.id)}
                >
                  <strong>{record.type || "Maintenance"}</strong>
                  <p className="page-subtitle">
                    {record.shopName || "Unknown shop"} • {record.vehicleProfileName || "Unknown vehicle"}
                  </p>
                  <div style={{ marginTop: 12 }}>Cost: {record.totalCost ?? "—"}</div>
                  <div style={{ marginTop: 6 }}>Odometer: {record.odometer ?? "—"}</div>
                  <div className="muted" style={{ marginTop: 8 }}>
                    {record.receiptPath ? "Receipt in Firebase Storage" : "No receipt"}
                  </div>
                </button>
              ))
            )}
          </div>

          <div className="card panel">
            <strong>Edit Maintenance Record</strong>
            <p className="page-subtitle">Update service metadata, costs, and reminders.</p>

            <div className="form-grid" style={{ marginTop: 16 }}>
              <label className="field">
                <span>Select maintenance record</span>
                <select
                  className="input"
                  value={selectedRecordID}
                  onChange={(event) => setSelectedRecordID(event.target.value)}
                >
                  {records.map((record) => (
                    <option key={record.id} value={record.id}>
                      {(record.type || "Maintenance") + " • " + (record.vehicleProfileName || "Unknown vehicle")}
                    </option>
                  ))}
                </select>
              </label>

              {formState ? (
                <>
                  <label className="field">
                    <span>Shop name</span>
                    <input
                      className="input"
                      value={formState.shopName}
                      onChange={(event) =>
                        setFormState({ ...formState, shopName: event.target.value })
                      }
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

                  <label className="field">
                    <span>Type</span>
                    <input
                      className="input"
                      value={formState.type}
                      onChange={(event) => setFormState({ ...formState, type: event.target.value })}
                    />
                  </label>

                  <label className="field">
                    <span>Other description</span>
                    <input
                      className="input"
                      value={formState.otherDescription}
                      onChange={(event) =>
                        setFormState({ ...formState, otherDescription: event.target.value })
                      }
                    />
                  </label>

                  <label className="field">
                    <span>Notes</span>
                    <textarea
                      className="textarea"
                      rows={4}
                      value={formState.notes}
                      onChange={(event) => setFormState({ ...formState, notes: event.target.value })}
                    />
                  </label>

                  <div className="grid" style={{ gridTemplateColumns: "repeat(3, minmax(0, 1fr))" }}>
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
                      <span>Odometer</span>
                      <input
                        className="input"
                        inputMode="decimal"
                        value={formState.odometer}
                        onChange={(event) => setFormState({ ...formState, odometer: event.target.value })}
                      />
                    </label>

                    <label className="field">
                      <span>Next service</span>
                      <input
                        className="input"
                        inputMode="decimal"
                        value={formState.nextServiceOdometer}
                        onChange={(event) =>
                          setFormState({ ...formState, nextServiceOdometer: event.target.value })
                        }
                      />
                    </label>
                  </div>

                  <label style={{ display: "flex", alignItems: "center", gap: 10 }}>
                    <input
                      type="checkbox"
                      checked={formState.reminderEnabled}
                      onChange={(event) =>
                        setFormState({ ...formState, reminderEnabled: event.target.checked })
                      }
                    />
                    Reminder enabled
                  </label>

                  {status ? <div className="muted">{status}</div> : null}

                  <button className="button" type="button" onClick={handleSave} disabled={saving}>
                    {saving ? "Saving…" : "Save Maintenance Record"}
                  </button>
                </>
              ) : (
                <div className="empty-state">No maintenance record selected.</div>
              )}
            </div>
          </div>
        </div>
      </NavShell>
    </AuthGuard>
  );
}
