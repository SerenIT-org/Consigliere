export function StatusWidget({ online }: { online?: boolean }) {
  if (online === undefined) return null;
  return (
    <span className={`widget widget-status ${online ? "online" : "offline"}`}>
      {online ? "● online" : "○ offline"}
    </span>
  );
}
