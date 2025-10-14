import { NextResponse } from "next/server";
import { getDb } from "@/lib/db";
import { toAgentSummary, toValidationSummary } from "@/lib/transformers";

const encoder = new TextEncoder();

export const runtime = "nodejs";

function serialize(data: unknown) {
  return encoder.encode(`data: ${JSON.stringify(data)}\n\n`);
}

export async function GET() {
  const db = getDb();

  let interval: NodeJS.Timeout | undefined;

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(encoder.encode("event: ping\ndata: ready\n\n"));

      let lastFingerprint = "";

      interval = setInterval(() => {
        try {
          const agents = db.getAllAgents().map((agent) => {
            const validation = agent.current_validation_id
              ? db.getValidationSession(agent.current_validation_id)
              : undefined;
            return toAgentSummary(agent, validation ?? null);
          });

          const validations = db
            .listValidationSessions()
            .map(toValidationSummary);

          const payload = { agents, validations, timestamp: Date.now() };
          const fingerprint = JSON.stringify(payload, (_, value) => value);

          if (fingerprint !== lastFingerprint) {
            controller.enqueue(encoder.encode("event: snapshot\n"));
            controller.enqueue(serialize(payload));
            lastFingerprint = fingerprint;
          }
        } catch (error) {
          console.error("[events] poll error", error);
        }
      }, 2000);

    },
    cancel() {
      if (interval) {
        clearInterval(interval);
      }
    },
  });

  return new NextResponse(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
    },
  });
}
