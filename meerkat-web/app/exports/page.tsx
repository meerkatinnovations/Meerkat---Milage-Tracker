"use client";

import { useEffect, useState } from "react";
import { AuthGuard } from "@/components/auth-guard";
import { NavShell } from "@/components/nav-shell";
import { useAuth } from "@/components/auth-provider";
import {
  fetchCollectionUnordered,
  FuelRecord,
  MaintenanceRecord,
  TripRecord
} from "@/lib/firestore";

function downloadFile(filename: string, contents: string, mimeType: string) {
  const blob = new Blob([contents], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

function toCSV(rows: Array<Record<string, unknown>>) {
  if (rows.length === 0) {
    return "";
  }

  const headers = Object.keys(rows[0]);
  const lines = [
    headers.join(","),
    ...rows.map((row) =>
      headers
        .map((header) => JSON.stringify(row[header] ?? ""))
        .join(",")
    )
  ];
  return lines.join("\n");
}

export default function ExportsPage() {
  const { user } = useAuth();
  const uid = user?.uid;
  const [trips, setTrips] = useState<TripRecord[]>([]);
  const [fuelEntries, setFuelEntries] = useState<FuelRecord[]>([]);
  const [maintenanceRecords, setMaintenanceRecords] = useState<MaintenanceRecord[]>([]);

  useEffect(() => {
    if (!uid) {
      return;
    }

    async function load() {
      const [nextTrips, nextFuelEntries, nextMaintenanceRecords] = await Promise.all([
        fetchCollectionUnordered<TripRecord>(uid, "trips"),
        fetchCollectionUnordered<FuelRecord>(uid, "fuelEntries"),
        fetchCollectionUnordered<MaintenanceRecord>(uid, "maintenanceRecords")
      ]);

      setTrips(nextTrips);
      setFuelEntries(nextFuelEntries);
      setMaintenanceRecords(nextMaintenanceRecords);
    }

    void load();
  }, [uid]);

  return (
    <AuthGuard>
      <NavShell
        title="Exports"
        subtitle="Download core data directly from the structured Firebase collections."
      >
        <div className="grid">
          <div className="card panel">
            <strong>Trips CSV</strong>
            <p className="page-subtitle">Export the synced trip table for desktop review.</p>
            <button
              className="button"
              style={{ marginTop: 14 }}
              onClick={() => downloadFile("trips.csv", toCSV(trips), "text/csv")}
            >
              Download Trips CSV
            </button>
          </div>

          <div className="card panel">
            <strong>Fuel JSON</strong>
            <p className="page-subtitle">Raw fuel entries including receipt path references.</p>
            <button
              className="button"
              style={{ marginTop: 14 }}
              onClick={() =>
                downloadFile("fuel.json", JSON.stringify(fuelEntries, null, 2), "application/json")
              }
            >
              Download Fuel JSON
            </button>
          </div>

          <div className="card panel">
            <strong>Maintenance JSON</strong>
            <p className="page-subtitle">Maintenance records ready for deeper reporting later.</p>
            <button
              className="button"
              style={{ marginTop: 14 }}
              onClick={() =>
                downloadFile(
                  "maintenance.json",
                  JSON.stringify(maintenanceRecords, null, 2),
                  "application/json"
                )
              }
            >
              Download Maintenance JSON
            </button>
          </div>
        </div>
      </NavShell>
    </AuthGuard>
  );
}
