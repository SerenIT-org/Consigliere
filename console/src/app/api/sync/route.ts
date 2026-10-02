import { NextResponse } from "next/server";
import { authzResponse, requireAdmin } from "@/lib/authz";
import { syncOverview } from "@/lib/outline/syncOverview";

// POST /api/sync -- regenerates the Outline overview table from the
// per-machine docs (see syncOverview.ts). Mutating, so admin-only with
// group re-validation against Pocket ID (see lib/authz.ts).
export async function POST() {
  try {
    await requireAdmin();
  } catch (err) {
    return authzResponse(err);
  }

  try {
    const result = await syncOverview();
    return NextResponse.json({ ok: true, ...result });
  } catch (err) {
    return NextResponse.json(
      { ok: false, error: err instanceof Error ? err.message : String(err) },
      { status: 500 },
    );
  }
}
