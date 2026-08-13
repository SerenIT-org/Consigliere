export { default } from "next-auth/middleware";

// Everything requires a Pocket ID session except the NextAuth routes
// themselves and Next's static assets.
export const config = {
  matcher: ["/((?!api/auth|_next/static|_next/image|favicon.ico).*)"],
};
