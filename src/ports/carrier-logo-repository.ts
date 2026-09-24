export interface CarrierLogoRepository {
  getMany(iatas: string[]): Promise<Record<string, string | null>>;
  canManage(iata: string): Promise<boolean>;
  upload(iata: string, image: Uint8Array): Promise<string>;
  setReference(iata: string, path: string | null): Promise<string | null>;
  deleteFile(path: string): Promise<void>;
}
export interface LogoImageProcessor { normalise(bytes: Uint8Array): Promise<Uint8Array> }
