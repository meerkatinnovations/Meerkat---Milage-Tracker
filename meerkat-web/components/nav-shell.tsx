"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { ReactNode } from "react";
import { logout } from "@/lib/auth";
import { useAuth } from "@/components/auth-provider";

const navigation = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/organization", label: "Organization" },
  { href: "/trips", label: "Trips" },
  { href: "/vehicles", label: "Vehicles" },
  { href: "/fuel", label: "Fuel" },
  { href: "/maintenance", label: "Maintenance" },
  { href: "/exports", label: "Exports" }
];

export function NavShell({
  title,
  subtitle,
  children
}: {
  title: string;
  subtitle: string;
  children: ReactNode;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const { user, organizationContext, isBusinessUser } = useAuth();

  async function handleSignOut() {
    await logout();
    router.replace("/login");
  }

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand-lockup">
          <img className="brand-logo" src="/meerkat-logo.jpeg" alt="Meerkat logo" />
          <div>
            <strong>Meerkat - Milage Tracker</strong>
            <div className="muted">
              {isBusinessUser ? "for Business" : "Customer Portal"}
            </div>
          </div>
        </div>

        <div className="nav-list">
          {navigation.map((item) => (
            <Link
              key={item.href}
              className={`nav-item${pathname === item.href ? " active" : ""}`}
              href={item.href}
            >
              {item.label}
            </Link>
          ))}
        </div>

        <div style={{ marginTop: 28 }} className="muted">
          Signed in as
          <div style={{ color: "var(--text)", marginTop: 6, wordBreak: "break-word" }}>
            {user?.email ?? "Unknown account"}
          </div>
        </div>

        {organizationContext ? (
          <div style={{ marginTop: 18 }} className="muted">
            Organization
            <div style={{ color: "var(--text)", marginTop: 6 }}>
              {organizationContext.organization.name}
            </div>
            <div style={{ marginTop: 4 }}>
              {organizationContext.membership.role === "accountManager" ? "Account Manager" : "Employee / Driver"}
            </div>
          </div>
        ) : null}

        <button className="button ghost" style={{ marginTop: 18 }} onClick={handleSignOut}>
          Sign out
        </button>
      </aside>

      <main className="content">
        <div className="topbar">
          <div>
            <h1 className="page-title">{title}</h1>
            <p className="page-subtitle">{subtitle}</p>
          </div>
          <div className="tag">
            {isBusinessUser
              ? "Meerkat - Milage Tracker for Business"
              : "app.meerkatinnovations.ca"}
          </div>
        </div>
        {children}
      </main>
    </div>
  );
}
