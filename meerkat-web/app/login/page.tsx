"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { loginWithApple, loginWithEmail, resetPassword } from "@/lib/auth";
import { useAuth } from "@/components/auth-provider";

export default function LoginPage() {
  const router = useRouter();
  const { user, loading } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [appleSubmitting, setAppleSubmitting] = useState(false);

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

  return (
    <div className="login-shell">
      <div className="card panel login-card">
        <div className="tag">Meerkat - Milage Tracker for Business</div>
        <h1 className="page-title" style={{ fontSize: "2.7rem", marginTop: 16 }}>
          Sign in to manage business fleet data
        </h1>
        <p className="page-subtitle">
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
      </div>
    </div>
  );
}
