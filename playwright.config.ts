import { defineConfig } from "@playwright/test";
export default defineConfig({ testDir: "./tests/browser", use: { baseURL: "http://127.0.0.1:3000" }, webServer: { command: "pnpm start --hostname 127.0.0.1", url: "http://127.0.0.1:3000/login", reuseExistingServer: !process.env.CI }, projects: [{ name: "chromium", use: { browserName: "chromium" } }] });
