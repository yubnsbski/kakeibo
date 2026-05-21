import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { runClassification, runManualTransactionInput } from "./inputAutomation";

type JsonBodyResult = { ok: true; body: unknown } | { ok: false };

function sendJson(res: ServerResponse, statusCode: number, payload: unknown): void {
  res.statusCode = statusCode;
  res.setHeader("content-type", "application/json; charset=utf-8");
  res.end(JSON.stringify(payload));
}

async function readJsonBody(req: IncomingMessage): Promise<JsonBodyResult> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }

  const text = Buffer.concat(chunks).toString("utf8");

  try {
    return { ok: true, body: text ? JSON.parse(text) : {} };
  } catch {
    return { ok: false };
  }
}

export async function handleRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
  if (req.method === "POST" && req.url === "/classify") {
    const parsed = await readJsonBody(req);
    if (!parsed.ok) {
      sendJson(res, 400, { error: "invalid_json" });
      return;
    }

    const result = runClassification(parsed.body as Parameters<typeof runClassification>[0]);
    sendJson(res, result.ok ? 200 : 400, result);
    return;
  }

  if (req.method === "POST" && req.url === "/api/manual-transactions/preview") {
    const parsed = await readJsonBody(req);
    if (!parsed.ok) {
      sendJson(res, 400, { error: "invalid_json" });
      return;
    }

    const result = runManualTransactionInput(parsed.body as Parameters<typeof runManualTransactionInput>[0]);
    if (result.ok) {
      sendJson(res, 200, { ok: true, output: result });
      return;
    }

    sendJson(res, 400, {
      ok: false,
      error: result.error,
      message: result.error
    });
    return;
  }

  sendJson(res, 404, { error: "not_found" });
}

export function createAppServer() {
  return createServer((req, res) => {
    handleRequest(req, res).catch(() => {
      sendJson(res, 500, { error: "internal_error" });
    });
  });
}
