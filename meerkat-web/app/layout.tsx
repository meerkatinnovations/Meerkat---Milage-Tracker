import type { Metadata } from "next";
import { ReactNode } from "react";
import { AuthProvider } from "@/components/auth-provider";
import "./globals.css";

export const metadata: Metadata = {
  title: "Meerkat Customer Portal",
  description: "Manage trips, vehicles, fuel, maintenance, and exports online.",
  icons: {
    icon: "/icon.png",
    apple: "/icon.png",
    shortcut: "/icon.png"
  }
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}
