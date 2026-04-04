import { TripRecord } from "@/lib/firestore";

function formatDistance(distanceMeters?: number, unitSystem?: string) {
  if (!distanceMeters) {
    return "—";
  }

  if (unitSystem === "miles") {
    return `${(distanceMeters / 1609.344).toFixed(1)} mi`;
  }

  return `${(distanceMeters / 1000).toFixed(1)} km`;
}

function formatDate(input?: { seconds: number }) {
  if (!input?.seconds) {
    return "—";
  }

  return new Date(input.seconds * 1000).toLocaleDateString();
}

type TripTableProps = {
  trips: TripRecord[];
  onSelectTrip?: (trip: TripRecord) => void;
  selectedTripID?: string;
  unitSystem?: string;
};

export function TripTable({ trips, onSelectTrip, selectedTripID, unitSystem }: TripTableProps) {
  if (trips.length === 0) {
    return <div className="empty-state">No trips have been synced for this account yet.</div>;
  }

  return (
    <div className="card panel table-wrap">
      <table>
        <thead>
          <tr>
            <th>Date</th>
            <th>Trip</th>
            <th>Vehicle</th>
            <th>Route</th>
            <th>Distance</th>
            <th>Odometer</th>
          </tr>
        </thead>
        <tbody>
          {trips.map((trip) => (
            <tr
              key={trip.id}
              onClick={onSelectTrip ? () => onSelectTrip(trip) : undefined}
              style={{
                cursor: onSelectTrip ? "pointer" : "default",
                backgroundColor:
                  selectedTripID === trip.id ? "rgba(242, 140, 40, 0.08)" : undefined
              }}
            >
              <td>{formatDate(trip.date)}</td>
              <td>{trip.name || trip.tripType || "Trip"}</td>
              <td>{trip.vehicleProfileName || "—"}</td>
              <td>
                {(trip.startAddress || "—") + " → " + (trip.endAddress || "—")}
              </td>
              <td>{formatDistance(trip.distanceMeters, unitSystem)}</td>
              <td>
                {trip.odometerStart ?? "—"} to {trip.odometerEnd ?? "—"}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
