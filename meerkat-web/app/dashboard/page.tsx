"use client";

import { useEffect, useState } from "react";
import { AuthGuard } from "@/components/auth-guard";
import { NavShell } from "@/components/nav-shell";
import {
  fetchCollection,
  fetchUserProfile,
  FuelRecord,
  MaintenanceRecord,
  TripRecord,
  UserProfile,
  VehicleRecord
} from "@/lib/firestore";
import { useAuth } from "@/components/auth-provider";
import { TripTable } from "@/components/trip-table";

function sortTripsNewestFirst(records: TripRecord[]) {
  return [...records].sort((lhs, rhs) => {
    const lhsDate = lhs.date?.seconds ?? 0;
    const rhsDate = rhs.date?.seconds ?? 0;
    return rhsDate - lhsDate;
  });
}

export default function DashboardPage() {
  const { user } = useAuth();
  const uid = user?.uid;
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [trips, setTrips] = useState<TripRecord[]>([]);
  const [vehicles, setVehicles] = useState<VehicleRecord[]>([]);
  const [fuelEntries, setFuelEntries] = useState<FuelRecord[]>([]);
  const [maintenanceRecords, setMaintenanceRecords] = useState<MaintenanceRecord[]>([]);

  useEffect(() => {
    if (!uid) {
      return;
    }
    const safeUID = uid;

    async function load() {
      const [nextProfile, nextTrips, nextVehicles, nextFuel, nextMaintenance] = await Promise.all([
        fetchUserProfile(safeUID),
        fetchCollection<TripRecord>(safeUID, "trips"),
        fetchCollection<VehicleRecord>(safeUID, "vehicles"),
        fetchCollection<FuelRecord>(safeUID, "fuelEntries"),
        fetchCollection<MaintenanceRecord>(safeUID, "maintenanceRecords")
      ]);

      setProfile(nextProfile);
      setTrips(sortTripsNewestFirst(nextTrips));
      setVehicles(nextVehicles);
      setFuelEntries(nextFuel);
      setMaintenanceRecords(nextMaintenance);
    }

    void load();
  }, [uid]);

  return (
    <AuthGuard>
      <NavShell
        title="Dashboard"
        subtitle="Review the same account data that is synced from the mobile app."
      >
        <div className="grid stats">
          <div className="card panel">
            <div className="muted">Trips</div>
            <p className="stat-value">{trips.length}</p>
          </div>
          <div className="card panel">
            <div className="muted">Vehicles</div>
            <p className="stat-value">{vehicles.filter((entry) => !entry.archived).length}</p>
          </div>
          <div className="card panel">
            <div className="muted">Fuel Entries</div>
            <p className="stat-value">{fuelEntries.length}</p>
          </div>
          <div className="card panel">
            <div className="muted">Maintenance</div>
            <p className="stat-value">{maintenanceRecords.length}</p>
          </div>
        </div>

        <div className="grid" style={{ marginTop: 22 }}>
          <div className="card panel">
            <strong>Account Profile</strong>
            <p className="page-subtitle">
              {profile?.displayName || user?.email || "Signed-in account"}
            </p>
            <div className="grid" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", marginTop: 14 }}>
              <div>
                <div className="muted">Country</div>
                <div>{profile?.selectedCountry || "—"}</div>
              </div>
              <div>
                <div className="muted">Currency</div>
                <div>{profile?.preferredCurrency || "—"}</div>
              </div>
              <div>
                <div className="muted">Units</div>
                <div>{profile?.unitSystem || "—"}</div>
              </div>
            </div>
          </div>
          <TripTable trips={trips.slice(0, 10)} unitSystem={profile?.unitSystem} />
        </div>
      </NavShell>
    </AuthGuard>
  );
}
