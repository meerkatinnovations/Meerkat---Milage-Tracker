import { TripRecord } from "@/lib/firestore";

function formatDistance(distanceMeters?: number) {
  if (!distanceMeters) {
    return "—";
  }

  return `${(distanceMeters / 1000).toFixed(1)} km`;
}

function formatDate(input?: { seconds: number }) {
  if (!input?.seconds) {
    return "—";
  }

  return new Date(input.seconds * 1000).toLocaleDateString();
}

export function TripTable({ trips }: { trips: TripRecord[] }) {
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
            <tr key={trip.id}>
              <td>{formatDate(trip.date)}</td>
              <td>{trip.name || trip.tripType || "Trip"}</td>
              <td>{trip.vehicleProfileName || "—"}</td>
              <td>
                {(trip.startAddress || "—") + " → " + (trip.endAddress || "—")}
              </td>
              <td>{formatDistance(trip.distanceMeters)}</td>
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
