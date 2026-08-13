import { NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { syncOverview } from "@/lib/outline/syncOverview";

// POST /api/sync — regenerates the Outline overview table from the
// per-machine docs (see syncOverview.ts). Callable from the UI's sync
// button, or on a schedule (e.g. a cron hitting this with a session
// cookie/service token — TODO once there's an actual scheduler wired up).
export async function POST() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  try {
    const result = await syncOverview();
    return NextResponse.json({ ok: true, ...result });
  } catch (err) {
    return NextResponse.json(
      { ok: false, error: err instanceof Error ? err.message : String(err) },
      { status: 500 }
    );
  }
}
