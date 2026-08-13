import type { DashboardLink } from "@/lib/providers/types";

export function DashboardLinksWidget({ links }: { links: DashboardLink[] }) {
  if (links.length === 0) return null;
  return (
    <div className="widget widget-dashboards">
      {links.map((l) => (
        <a key={l.url} href={l.url} target="_blank" rel="noreferrer">
          {l.label}
        </a>
      ))}
    </div>
  );
}
