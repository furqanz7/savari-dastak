import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";

export default defineConfig(({ command }) => {
  if (command !== "serve") throw new Error("The isolated Admin fixture is never a production entrypoint.");
  return {
    plugins: [react()],
    resolve: { alias: [
      { find: /^\.\/dastakV1$/, replacement: fileURLToPath(new URL("./v1.ts", import.meta.url)) },
      { find: /^\.\/admin$/, replacement: fileURLToPath(new URL("./legacy.ts", import.meta.url)) },
      { find: /^\.\/earnings$/, replacement: fileURLToPath(new URL("./earnings.ts", import.meta.url)) },
    ] },
    server: { host: "127.0.0.1", port: 4179, strictPort: true },
  };
});
