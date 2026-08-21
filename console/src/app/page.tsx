import { getProvider } from "@/lib/providers/registry";
import { getTailscaleStatusByHostname } from "@/lib/tailscale";
import { TileGrid } from "@/components/TileGrid";
import { SyncButton } from "@/components/SyncButton";

export const dynamic = "force-dynamic"; // fleet state changes outside of a rebuild

export default async function DashboardPage() {
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
        <SyncButton />
      </header>
      <TileGrid machines={machines} onlineByHostname={onlineByHostname} />
    </main>
  );
}
