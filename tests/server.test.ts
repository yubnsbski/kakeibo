import { afterEach, describe, expect, it } from "vitest";
import { createAppServer } from "../src/server";

const localFetch = globalThis.fetch;

let activeServer: import("node:http").Server | null = null;

afterEach(async () => {
  if (activeServer) {
    await new Promise<void>((resolve, reject) => {
      activeServer?.close((err) => (err ? reject(err) : resolve()));
    });
    activeServer = null;
  }
});

async function startTestServer(): Promise<{ baseUrl: string }> {
  const server = createAppServer();
  await new Promise<void>((resolve) => server.listen(0, resolve));
  activeServer = server;

  const address = server.address();
  if (!address || typeof address === "string") {
    throw new Error("failed to bind test server");
  }

  return { baseUrl: `http://127.0.0.1:${address.port}` };
}

describe("server /classify", () => {
  it("returns classification for valid request", async () => {
    const { baseUrl } = await startTestServer();

    const response = await localFetch(`${baseUrl}/classify`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ merchantRaw: "セブンイレブン", items: ["おにぎり"] })
    });

    expect(response.status).toBe(200);
    const data = (await response.json()) as { category: string | null; needsReview: boolean };
    expect(data.category).toBe("食費");
    expect(data.needsReview).toBe(false);
  });

  it("returns 400 when merchantRaw is missing", async () => {
    const { baseUrl } = await startTestServer();

    const response = await localFetch(`${baseUrl}/classify`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ items: ["おにぎり"] })
    });

    expect(response.status).toBe(400);
    const data = (await response.json()) as { error: string };
    expect(data.error).toBe("invalid_request");
  });
});
