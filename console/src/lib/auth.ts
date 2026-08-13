import type { NextAuthOptions } from "next-auth";

// Pocket ID (https://github.com/pocket-id/pocket-id) speaks standard OIDC,
// so this is a generic OAuth provider pointed at its discovery document
// rather than anything Pocket-ID-specific.
//
// NOTE: `profile()` below assumes standard OIDC claims (sub/name/email/
// picture) — verify against what Pocket ID's userinfo endpoint actually
// returns on first login and adjust if needed.
export const authOptions: NextAuthOptions = {
  providers: [
    {
      id: "pocket-id",
      name: "Pocket ID",
      type: "oauth",
      wellKnown: `${process.env.POCKET_ID_URL}/.well-known/openid-configuration`,
      clientId: process.env.POCKET_ID_CLIENT_ID,
      clientSecret: process.env.POCKET_ID_CLIENT_SECRET,
      authorization: { params: { scope: "openid email profile" } },
      idToken: true,
      checks: ["pkce", "state"],
      profile(profile: { sub: string; name?: string; preferred_username?: string; email?: string; picture?: string }) {
        return {
          id: profile.sub,
          name: profile.name ?? profile.preferred_username ?? profile.sub,
          email: profile.email,
          image: profile.picture,
        };
      },
    },
  ],
  session: { strategy: "jwt" },
  secret: process.env.NEXTAUTH_SECRET,
};
