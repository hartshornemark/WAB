import { AuthenticationRequired, CarrierUnavailable, SignInFailed } from "@/domain/models";
import type { AuthService } from "@/ports/auth-service";
import type { CarrierRepository } from "@/ports/carrier-repository";
import type { CarrierLogoRepository } from "@/ports/carrier-logo-repository";
export function createCarrierConfiguration(auth: AuthService, carriers: CarrierRepository, logos?: CarrierLogoRepository) {
  async function requireUser() {
    const user = await auth.currentUser();
    if (!user) throw new AuthenticationRequired();
    return user;
  }
  return {
    currentUser: () => auth.currentUser(),
    async signIn(email: string, password: string) {
      const normalised = email.trim();
      if (!normalised || normalised.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalised) || !password || password.length > 1024) throw new SignInFailed();
      await auth.signIn(normalised, password);
    },
    signOut: () => auth.signOut(),
    async listCarriers() {
      const user = await requireUser();
      const list = await carriers.listAuthorised();
      if (!logos) return { user, carriers: list };
      const branding = await logos.getMany(list.map(carrier => carrier.iata));
      return { user, carriers: list.map(carrier => ({ ...carrier, ...(branding[carrier.iata] ? { logoUrl: branding[carrier.iata] } : {}) })) };
    },
    async selectCarrier(iata: string) {
      const user = await requireUser();
      if (!iata || iata.length > 32) throw new CarrierUnavailable();
      // Selection is context only. The repository re-queries under the user's RLS.
      const carrier = await carriers.findAuthorised(iata);
      if (!carrier) throw new CarrierUnavailable();
      const branding = logos ? (await logos.getMany([iata]))[iata] : undefined;
      return { user, carrier: { ...carrier, ...(branding ? { logoUrl: branding } : {}) } };
    },
  };
}
