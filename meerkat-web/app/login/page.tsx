"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { loginWithApple, loginWithEmail, resetPassword } from "@/lib/auth";
import { useAuth } from "@/components/auth-provider";

export default function LoginPage() {
  const APP_STORE_URL = "https://apps.apple.com/ca/app/meerkat-milage-tracker/id6760921171";
  const APP_SCHEME_URL = "meerkat-mileage-tracker://";
  const router = useRouter();
  const { user, loading } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [appleSubmitting, setAppleSubmitting] = useState(false);
  const [appLaunchMessage, setAppLaunchMessage] = useState(
    "Open the app directly, or continue with web sign-in below.",
  );

  useEffect(() => {
    if (!loading && user) {
      router.replace("/dashboard");
    }
  }, [loading, router, user]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError("");
    setMessage("");

    try {
      await loginWithEmail(email, password);
      router.replace("/dashboard");
    } catch (submitError) {
      setError(submitError instanceof Error ? submitError.message : "Unable to sign in.");
    } finally {
      setSubmitting(false);
    }
  }

  async function handleResetPassword() {
    if (!email) {
      setError("Enter your email first, then try reset.");
      return;
    }

    try {
      await resetPassword(email);
      setMessage("Password reset email sent.");
      setError("");
    } catch (resetError) {
      setError(resetError instanceof Error ? resetError.message : "Unable to send reset email.");
    }
  }

  async function handleAppleSignIn() {
    setAppleSubmitting(true);
    setError("");
    setMessage("");

    try {
      await loginWithApple();
      router.replace("/dashboard");
    } catch (signInError) {
      setError(signInError instanceof Error ? signInError.message : "Unable to sign in with Apple.");
    } finally {
      setAppleSubmitting(false);
    }
  }

  function openAppWithFallback() {
    const mobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);
    if (!mobile) {
      setAppLaunchMessage("For best results use iPhone/iPad, or download from the App Store.");
      return;
    }

    const start = Date.now();
    setAppLaunchMessage("Trying to open the Meerkat app...");
    window.location.href = APP_SCHEME_URL;

    window.setTimeout(() => {
      const elapsed = Date.now() - start;
      if (elapsed < 1800) {
        setAppLaunchMessage("App not detected. Redirecting to App Store...");
        window.location.href = APP_STORE_URL;
      }
    }, 1200);
  }

  return (
    <div className="login-shell">
      <div className="login-layout">
        <section className="card panel login-marketing">
          <div className="tag">Meerkat Mileage Tracker</div>
          <h1 className="page-title" style={{ fontSize: "2.7rem", marginTop: 16 }}>
            Log mileage with less admin, right from your iPhone.
          </h1>
          <p className="page-subtitle">
            Use Meerkat in the app for trip tracking, fuel economy, vehicle insights, and tax-ready logs.
          </p>
          <div className="login-app-actions">
            <button className="button" type="button" onClick={openAppWithFallback}>
              Open Meerkat App
            </button>
            <a className="button secondary" href={APP_STORE_URL}>
              Download on the App Store
            </a>
          </div>
          <p className="muted" style={{ marginTop: 12 }}>
            {appLaunchMessage}
          </p>
        </section>

        <section className="card panel login-card">
          <div className="tag">Portal Sign In</div>
          <h2 style={{ margin: "16px 0 0", fontFamily: "var(--font-display)", fontSize: "1.8rem" }}>
            Continue on web
          </h2>
          <p className="page-subtitle" style={{ marginTop: 10 }}>
            Use the same Firebase-backed account you use in the mobile app.
          </p>

          <form className="form-grid" style={{ marginTop: 22 }} onSubmit={handleSubmit}>
            <label className="field">
              <span>Email</span>
              <input
                className="input"
                type="email"
                autoComplete="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                required
              />
            </label>

            <label className="field">
              <span>Password</span>
              <input
                className="input"
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                required
              />
            </label>

            {error ? <div style={{ color: "#9f2500" }}>{error}</div> : null}
            {message ? <div style={{ color: "var(--brand-strong)" }}>{message}</div> : null}

            <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
              <button className="button" type="submit" disabled={submitting}>
                {submitting ? "Signing in…" : "Sign in"}
              </button>
              <button className="button secondary" type="button" onClick={handleResetPassword}>
                Reset password
              </button>
              <button
                className="button ghost"
                type="button"
                onClick={handleAppleSignIn}
                disabled={appleSubmitting}
              >
                {appleSubmitting ? "Connecting Apple…" : "Sign in with Apple"}
              </button>
            </div>
          </form>
        </section>
      </div>
    </div>
  );
}
