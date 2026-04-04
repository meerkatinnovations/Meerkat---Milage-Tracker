import {
  collection,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  Timestamp
} from "firebase/firestore";
import { db } from "@/lib/firebase";

export type UserProfile = {
  email?: string;
  displayName?: string;
  selectedCountry?: string;
  preferredCurrency?: string;
  unitSystem?: string;
  activeVehicleID?: string;
  activeDriverID?: string;
};

export type TripRecord = {
  id: string;
  name?: string;
  tripType?: string;
  vehicleProfileName?: string;
  driverName?: string;
  startAddress?: string;
  endAddress?: string;
  details?: string;
  odometerStart?: number;
  odometerEnd?: number;
  distanceMeters?: number;
  date?: { seconds: number };
  updatedAt?: { seconds: number };
};

export type VehicleRecord = {
  id: string;
  displayName?: string;
  profileName?: string;
  make?: string;
  model?: string;
  numberPlate?: string;
  startingOdometerReading?: number;
  archived?: boolean;
  updatedAt?: { seconds: number };
};

export type FuelRecord = {
  id: string;
  station?: string;
  vehicleProfileName?: string;
  volume?: number;
  totalCost?: number;
  odometer?: number;
  receiptPath?: string;
  updatedAt?: { seconds: number };
};

export type MaintenanceRecord = {
  id: string;
  shopName?: string;
  vehicleProfileName?: string;
  type?: string;
  otherDescription?: string;
  notes?: string;
  totalCost?: number;
  odometer?: number;
  receiptPath?: string;
  reminderEnabled?: boolean;
  nextServiceOdometer?: number;
  updatedAt?: { seconds: number };
};

export async function fetchUserProfile(uid: string) {
  const snapshot = await getDoc(doc(db, "users", uid));
  return (snapshot.data() ?? null) as UserProfile | null;
}

export async function fetchCollection<T>(uid: string, collectionName: string) {
  const snapshot = await getDocs(
    query(collection(db, "users", uid, collectionName), orderBy("updatedAt", "desc"))
  );
  return snapshot.docs.map((entry) => entry.data() as T);
}

export async function fetchCollectionUnordered<T>(uid: string, collectionName: string) {
  const snapshot = await getDocs(collection(db, "users", uid, collectionName));
  return snapshot.docs.map((entry) => entry.data() as T);
}

export type TripUpdateInput = {
  id: string;
  name: string;
  tripType: string;
  vehicleProfileName: string;
  driverName: string;
  startAddress: string;
  endAddress: string;
  details: string;
  odometerStart: number;
  odometerEnd: number;
  distanceMeters: number;
  date: Date;
};

export type VehicleUpdateInput = {
  id: string;
  profileName: string;
  make: string;
  model: string;
  color: string;
  numberPlate: string;
  startingOdometerReading: number;
  archived: boolean;
};

export type FuelUpdateInput = {
  id: string;
  station: string;
  vehicleProfileName: string;
  volume: number;
  totalCost: number;
  odometer: number;
};

export type MaintenanceUpdateInput = {
  id: string;
  shopName: string;
  vehicleProfileName: string;
  type: string;
  otherDescription: string;
  notes: string;
  totalCost: number;
  odometer: number;
  reminderEnabled: boolean;
  nextServiceOdometer?: number;
};

export async function saveTrip(uid: string, trip: TripUpdateInput) {
  await setDoc(
    doc(db, "users", uid, "trips", trip.id),
    {
      id: trip.id,
      name: trip.name,
      tripType: trip.tripType,
      vehicleProfileName: trip.vehicleProfileName,
      driverName: trip.driverName,
      startAddress: trip.startAddress,
      endAddress: trip.endAddress,
      details: trip.details,
      odometerStart: trip.odometerStart,
      odometerEnd: trip.odometerEnd,
      distanceMeters: trip.distanceMeters,
      date: Timestamp.fromDate(trip.date),
      updatedAt: serverTimestamp()
    },
    { merge: true }
  );
}

export async function saveVehicle(uid: string, vehicle: VehicleUpdateInput) {
  await setDoc(
    doc(db, "users", uid, "vehicles", vehicle.id),
    {
      id: vehicle.id,
      profileName: vehicle.profileName,
      displayName: vehicle.profileName || [vehicle.make, vehicle.model].filter(Boolean).join(" "),
      make: vehicle.make,
      model: vehicle.model,
      color: vehicle.color,
      numberPlate: vehicle.numberPlate,
      startingOdometerReading: vehicle.startingOdometerReading,
      archived: vehicle.archived,
      updatedAt: serverTimestamp()
    },
    { merge: true }
  );
}

export async function saveFuelEntry(uid: string, entry: FuelUpdateInput) {
  await setDoc(
    doc(db, "users", uid, "fuelEntries", entry.id),
    {
      id: entry.id,
      station: entry.station,
      vehicleProfileName: entry.vehicleProfileName,
      volume: entry.volume,
      totalCost: entry.totalCost,
      odometer: entry.odometer,
      updatedAt: serverTimestamp()
    },
    { merge: true }
  );
}

export async function saveMaintenanceRecord(uid: string, record: MaintenanceUpdateInput) {
  await setDoc(
    doc(db, "users", uid, "maintenanceRecords", record.id),
    {
      id: record.id,
      shopName: record.shopName,
      vehicleProfileName: record.vehicleProfileName,
      type: record.type,
      otherDescription: record.otherDescription,
      notes: record.notes,
      totalCost: record.totalCost,
      odometer: record.odometer,
      reminderEnabled: record.reminderEnabled,
      nextServiceOdometer: record.nextServiceOdometer ?? null,
      updatedAt: serverTimestamp()
    },
    { merge: true }
  );
}
