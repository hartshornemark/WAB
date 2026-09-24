export interface AuthenticatedUser { id: string; email: string | null; displayName?: string | null }
export interface Carrier { iata: string; name: string; icao: string; logoUrl?: string | null }
export class AuthenticationRequired extends Error {}
export class CarrierUnavailable extends Error {}
export class DataUnavailable extends Error {}
export class SignInFailed extends Error {}

export class LogoInputError extends Error {}
export class LogoAccessDenied extends Error {}
