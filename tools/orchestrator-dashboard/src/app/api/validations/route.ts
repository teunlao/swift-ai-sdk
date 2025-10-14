import { NextResponse } from "next/server";
import { getDb } from "@/lib/db";
import type { ValidationStatus } from "@/lib/db";
import { toValidationSummary } from "@/lib/transformers";

export const runtime = "nodejs";

export async function GET(request: Request) {
  const db = getDb();
  const url = new URL(request.url);
  const statusFilter = url.searchParams.get("status") ?? undefined;
  const executorFilter = url.searchParams.get("executorId") ?? undefined;
  const validatorFilter = url.searchParams.get("validatorId") ?? undefined;

  const allowedStatuses: ValidationStatus[] = ["pending", "in_progress", "approved", "rejected"];
  const status = statusFilter && allowedStatuses.includes(statusFilter as ValidationStatus)
    ? (statusFilter as ValidationStatus)
    : undefined;

  const sessions = db.listValidationSessions({
    status,
    executor_id: executorFilter ?? undefined,
    validator_id: validatorFilter ?? undefined,
  });

  return NextResponse.json({
    validations: sessions.map(toValidationSummary),
  });
}
