import "server-only";
import type { AuthService } from "@/ports/auth-service";
import { DataUnavailable, SignInFailed } from "@/domain/models";
import type { RequestClient } from "./server";
export function createAuthAdapter(client: RequestClient): AuthService {
  return {
    async currentUser() {
      // Fresh server lookup detects revoked sessions; never trust cookie getSession().user.
      const { data, error } = await client.auth.getUser();
      if (error) {
        if (error.name === "AuthSessionMissingError" || error.status === 400 || error.status === 401 || error.status === 403) return null;
        throw new DataUnavailable("Authentication is temporarily unavailable.");
      }
      if (!data.user || data.user.is_anonymous) return null;
      // Profile presentation only; authorization continues to use identity and RLS.
      const { data: name, error: nameError } = await client.schema("Basic_Carrier_Record").rpc("current_display_name", {});
      const displayName = !nameError && typeof name === "string" && name.trim() ? name.trim() : null;
      return { id: data.user.id, email: data.user.email ?? null, displayName };
    },
    async signIn(email, password) {
      const { error } = await client.auth.signInWithPassword({ email, password });
      if (error) throw new SignInFailed();
    },
    async signOut() {
      const { error } = await client.auth.signOut({ scope: "local" });
      if (error) throw new DataUnavailable("Sign out failed. Please try again.");
    },
  };
}
