import { afterEach, describe, expect, test } from "vitest";
import { createAppServer } from "../src/server";

const servers: Array<ReturnType<typeof createAppServer>> = [];

afterEach(async () => {
  await Promise.all(
    servers.map(
      (server) =>
        new Promise<void>((resolve, reject) => {
          server.close((err) => (err ? reject(err) : resolve()));
        })
    )
  );
  servers.length = 0;
});

async function startServer() {
  const server = createAppServer();
  servers.push(server);

  await new Promise<void>((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve());
  });

  const address = server.address();
  if (!address || typeof address === "string") throw new Error("failed to bind test server");

  return `http://127.0.0.1:${address.port}`;
}

describe("server", () => {
  test("POST /api/manual-transactions/preview with valid expense returns 200 + ok:true", async () => {
    const base = await startServer();

    const response = await fetch(`${base}/api/manual-transactions/preview`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        merchantRaw: "セブンイレブン 渋谷店",
        totalAmount: 620,
        purchasedAt: "2026-05-16",
        txType: "expense",
        items: [{ name: "おにぎり", amount: 200, category: "食費" }]
      })
    });

    const payload = await response.json();
    expect(response.status).toBe(200);
    expect(payload.ok).toBe(true);
    expect(payload.output.allocationInput.amount).toBe(620);
  });

  test("POST /api/manual-transactions/preview income returns 400 + ok:false", async () => {
    const base = await startServer();

    const response = await fetch(`${base}/api/manual-transactions/preview`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        merchantRaw: "給与",
        totalAmount: 300000,
        purchasedAt: "2026-05-16",
        txType: "income",
        items: []
      })
    });

    const payload = await response.json();
    expect(response.status).toBe(400);
    expect(payload.ok).toBe(false);
    expect(payload.error).toBe("UNSUPPORTED_TRANSACTION_TYPE");
  });

  test("POST /api/manual-transactions/preview validation error returns 400 + ok:false", async () => {
    const base = await startServer();

    const response = await fetch(`${base}/api/manual-transactions/preview`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        merchantRaw: "",
        totalAmount: 100,
        purchasedAt: "2026/05/16",
        txType: "expense",
        items: []
      })
    });

    const payload = await response.json();
    expect(response.status).toBe(400);
    expect(payload.ok).toBe(false);
    expect(payload.error).toBe("missing_merchant");
  });

  test("POST /api/manual-transactions/preview with invalid json returns 400", async () => {
    const base = await startServer();

    const response = await fetch(`${base}/api/manual-transactions/preview`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: '{"merchantRaw":"x"'
    });

    const payload = await response.json();
    expect(response.status).toBe(400);
    expect(payload).toEqual({ error: "invalid_json" });
  });

  test("POST /classify still works", async () => {
    const base = await startServer();

    const response = await fetch(`${base}/classify`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        merchantRaw: "セブンイレブン",
        items: ["おにぎり"],
        totalAmount: 450,
        purchasedAt: "2026-05-16"
      })
    });

    const payload = await response.json();
    expect(response.status).toBe(200);
    expect(payload.ok).toBe(true);
    expect(payload.output.category).toBe("食費");
  });
});
