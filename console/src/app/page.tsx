import { redirect } from "next/navigation";
import { AuthzError, requireViewer } from "@/lib/authz";
import { getProvider } from "@/lib/providers/registry";
import { getTailscaleStatusByHostname } from "@/lib/tailscale";
import { TileGrid } from "@/components/TileGrid";
import { SyncButton } from "@/components/SyncButton";

export const dynamic = "force-dynamic"; // fleet state changes outside of a rebuild

export default async function DashboardPage() {
  // Middleware only keeps anonymous browsers out; this is the real gate.
  let isAdmin = false;
  try {
    isAdmin = (await requireViewer()).isAdmin;
  } catch (err) {
    if (err instanceof AuthzError && err.status === 401) redirect("/api/auth/signin");
    if (err instanceof AuthzError) {
      return (
        <main className="page">
          <h1>Consigliere</h1>
          <p className="empty-state">Access denied: {err.message}.</p>
        </main>
      );
    }
    throw err;
  }

  const [machines, tsStatus] = await Promise.all([
    getProvider().listMachines(),
    getTailscaleStatusByHostname(),
  ]);

  const onlineByHostname = new Map<string, boolean>();
  for (const [hostname, device] of tsStatus) {
    onlineByHostname.set(hostname, device.online);
  }

  return (
    <main className="page">
      <header className="page-header">
        <h1>Consigliere</h1>
        {isAdmin && <SyncButton />}
      </header>
      <TileGrid machines={machines} onlineByHostname={onlineByHostname} />
    </main>
  );
}
