"use client";

import { onAuthStateChanged, User } from "firebase/auth";
import { createContext, ReactNode, useContext, useEffect, useState } from "react";
import { auth } from "@/lib/firebase";
import {
  fetchOrganizationContextForUser,
  fetchUserProfile,
  OrganizationContext,
  UserProfile
} from "@/lib/firestore";

type AuthContextValue = {
  user: User | null;
  loading: boolean;
  organizationContext: OrganizationContext | null;
  isBusinessUser: boolean;
};

const AuthContext = createContext<AuthContextValue>({
  user: null,
  loading: true,
  organizationContext: null,
  isBusinessUser: false
});

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [organizationContext, setOrganizationContext] = useState<OrganizationContext | null>(null);
  const [userProfile, setUserProfile] = useState<UserProfile | null>(null);

  const isBusinessUser =
    Boolean(organizationContext) ||
    userProfile?.accountSubscriptionType === "business" ||
    userProfile?.hasBusinessSubscription === true ||
    Boolean(userProfile?.businessProfile);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (nextUser) => {
      setUser(nextUser);

      if (nextUser?.email) {
        const [nextProfile, nextContext] = await Promise.all([
          fetchUserProfile(nextUser.uid),
          fetchOrganizationContextForUser(
            nextUser.uid,
            nextUser.email,
            nextUser.displayName
          )
        ]);
        setUserProfile(nextProfile);
        setOrganizationContext(nextContext);
      } else {
        setUserProfile(null);
        setOrganizationContext(null);
      }

      setLoading(false);
    });

    return unsubscribe;
  }, []);

  return (
    <AuthContext.Provider value={{ user, loading, organizationContext, isBusinessUser }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
