"use client";

import { useState } from "react";

export function SyncButton() {
  const [status, setStatus] = useState<"idle" | "syncing" | "done" | "error">("idle");

  async function sync() {
    setStatus("syncing");
    try {
      const res = await fetch("/api/sync", { method: "POST" });
      setStatus(res.ok ? "done" : "error");
    } catch {
      setStatus("error");
    } finally {
      setTimeout(() => setStatus("idle"), 2500);
    }
  }

  const label = { idle: "Sync overview", syncing: "Syncing…", done: "✓ Synced", error: "✗ Failed" }[
    status
  ];

  return (
    <button className="sync-button" onClick={sync} disabled={status === "syncing"}>
      {label}
    </button>
  );
}
