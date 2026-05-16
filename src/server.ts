import http = require("node:http");
import { classifyReceipt } from "./classifyReceipt";
import type { ReceiptInput } from "./types";

const DEFAULT_PORT = 3000;

function readRequestBody(req: http.IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Uint8Array[] = [];

    req.on("data", (chunk: Uint8Array) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function writeJson(res: http.ServerResponse, statusCode: number, body: unknown): void {
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.end(JSON.stringify(body));
}

function isValidReceiptInput(value: unknown): value is ReceiptInput {
  if (!value || typeof value !== "object") return false;
  const v = value as Partial<ReceiptInput>;

  if (typeof v.merchantRaw !== "string") return false;
  if (v.items !== undefined && !Array.isArray(v.items)) return false;
  if (Array.isArray(v.items) && v.items.some((item) => typeof item !== "string")) return false;

  return true;
}

export function createAppServer(): http.Server {
  return http.createServer(async (req, res) => {
    if (req.method === "OPTIONS") {
      res.statusCode = 204;
      res.setHeader("Access-Control-Allow-Origin", "*");
      res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
      res.setHeader("Access-Control-Allow-Headers", "Content-Type");
      res.end();
      return;
    }

    if (req.method !== "POST" || req.url !== "/classify") {
      writeJson(res, 404, { error: "not_found" });
      return;
    }

    try {
      const raw = await readRequestBody(req);
      const parsed: unknown = raw ? JSON.parse(raw) : {};

      if (!isValidReceiptInput(parsed)) {
        writeJson(res, 400, { error: "invalid_request" });
        return;
      }

      const result = classifyReceipt(parsed);
      writeJson(res, 200, result);
    } catch (_error) {
      writeJson(res, 400, { error: "invalid_json" });
    }
  });
}

export function startServer(port = DEFAULT_PORT): http.Server {
  const server = createAppServer();
  server.listen(port);
  return server;
}

if (require.main === module) {
  const port = Number(process.env.PORT ?? DEFAULT_PORT);
  startServer(port);
  process.stdout.write(`kakeibo server listening on http://localhost:${port}\n`);
}
