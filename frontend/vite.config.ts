import { readFileSync } from "node:fs";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const httpsKeyPath = process.env.KAKEIBO_HTTPS_KEY?.trim();
const httpsCertPath = process.env.KAKEIBO_HTTPS_CERT?.trim();

if ((httpsKeyPath && !httpsCertPath) || (!httpsKeyPath && httpsCertPath)) {
  throw new Error(
    "KAKEIBO_HTTPS_KEY と KAKEIBO_HTTPS_CERT は両方指定してください",
  );
}

const https =
  httpsKeyPath && httpsCertPath
    ? {
        key: readFileSync(httpsKeyPath),
        cert: readFileSync(httpsCertPath),
      }
    : undefined;

export default defineConfig({
  plugins: [react()],
  server: {
    host: "0.0.0.0",
    port: 5173,
    strictPort: true,
    https,
    proxy: {
      "/api": {
        target: "http://127.0.0.1:8000",
        changeOrigin: true,
      },
    },
  },
});
