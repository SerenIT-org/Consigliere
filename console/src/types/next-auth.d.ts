import type { DefaultSession } from "next-auth";

declare module "next-auth" {
  interface Session {
    accessToken?: string;
    /** Unix seconds when the provider access token expires, if known. */
    accessTokenExpires?: number;
    user: {
      /** Pocket ID subject. */
      sub: string;
      /** Convenience copy of the claim. Never the basis for an authorization decision. */
      groups: string[];
    } & DefaultSession["user"];
  }
}

declare module "next-auth/jwt" {
  interface JWT {
    accessToken?: string;
    accessTokenExpires?: number;
    groups?: string[];
  }
}
