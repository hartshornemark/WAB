import type { AuthenticatedUser } from "@/domain/models";
export interface AuthService {
  currentUser(): Promise<AuthenticatedUser | null>;
  signIn(email: string, password: string): Promise<void>;
  signOut(): Promise<void>;
}
