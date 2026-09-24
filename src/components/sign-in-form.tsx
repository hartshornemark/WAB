"use client";
import { useActionState } from "react";
import { signIn } from "@/app/actions";
export function SignInForm() {
  const [state, action, pending] = useActionState(signIn, { error: "" });
  return <form action={action} className="sign-in-form">
    <label htmlFor="email">Email</label>
    <input id="email" name="email" type="email" autoComplete="username" required maxLength={254} placeholder="you@organisation.com" />
    <label htmlFor="password">Password</label>
    <input id="password" name="password" type="password" autoComplete="current-password" required maxLength={1024} />
    <div role="status" aria-live="polite" className="form-message">{state.error}</div>
    <button disabled={pending} type="submit">{pending ? "Signing in…" : "Sign in →"}</button>
  </form>;
}
