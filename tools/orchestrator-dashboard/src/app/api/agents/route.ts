import { NextResponse } from "next/server";
import { getDb } from "@/lib/db";
import { toAgentSummary } from "@/lib/transformers";

export const runtime = "nodejs";

export async function GET(request: Request) {
  const db = getDb();
  const url = new URL(request.url);
  const statusFilter = url.searchParams.get("status");
  const roleFilter = url.searchParams.get("role");

  const agents = db.getAllAgents({
    status: statusFilter ?? undefined,
    role: roleFilter ?? undefined,
  });

  const payload = agents.map((agent) => {
    const validation = agent.current_validation_id
      ? db.getValidationSession(agent.current_validation_id)
      : undefined;
    return toAgentSummary(agent, validation ?? null);
  });

  return NextResponse.json({ agents: payload });
}
