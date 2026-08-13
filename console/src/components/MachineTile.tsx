import type { Machine } from "@/lib/providers/types";
import { DashboardLinksWidget, KvmWidget, SshLaunchWidget, StatusWidget } from "./widgets";

export function MachineTile({ machine, online }: { machine: Machine; online?: boolean }) {
  return (
    <article className="tile">
      <header className="tile-header">
        <h2>{machine.hostname}</h2>
        <StatusWidget online={online} />
      </header>

      {machine.role && <p className="tile-role">{machine.role}</p>}

      {machine.tags.length > 0 && (
        <ul className="tile-tags">
          {machine.tags.map((t) => (
            <li key={t}>{t}</li>
          ))}
        </ul>
      )}

      <div className="tile-actions">
        <SshLaunchWidget host={machine.tailscaleAddrs[0] ?? machine.hostname} />
        {machine.kvmUrl && <KvmWidget url={machine.kvmUrl} />}
      </div>

      <DashboardLinksWidget links={machine.dashboardLinks} />

      {machine.sourceUrl && (
        <a className="tile-edit" href={machine.sourceUrl} target="_blank" rel="noreferrer">
          Edit in Outline →
        </a>
      )}
    </article>
  );
}
