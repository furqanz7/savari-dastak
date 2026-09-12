import { defineConfig } from "vitest/config";
import { loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import { metadataForVariant } from "./src/releaseMetadata";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  const variant = env.VITE_APP_VARIANT || "savari-passenger";
  const metadata = metadataForVariant(variant);
  const provenance = {
    gitSha: env.VERCEL_GIT_COMMIT_SHA || env.GIT_COMMIT_SHA || "local",
    variant,
    environment: env.VERCEL_ENV || env.VITE_APP_ENVIRONMENT || mode,
    deploymentId: env.VERCEL_DEPLOYMENT_ID || env.DEPLOYMENT_ID || "local",
  };
  return {
    plugins: [react(), {
      name: "dastak-release-metadata",
      transformIndexHtml: {
        order: "pre",
        handler(html) {
          return {
            html: html
              .replace("<title>Marketplace</title>", `<title>${metadata.title}</title>`)
              .replace('content="Secure access to Dastak and Savari."', `content="${metadata.description}"`),
            tags: [
              { tag: "meta", attrs: { name: "application-name", content: metadata.applicationName }, injectTo: "head" },
              { tag: "meta", attrs: { name: "dastak:git-sha", content: provenance.gitSha }, injectTo: "head" },
              { tag: "meta", attrs: { name: "dastak:variant", content: provenance.variant }, injectTo: "head" },
              { tag: "meta", attrs: { name: "dastak:environment", content: provenance.environment }, injectTo: "head" },
              { tag: "meta", attrs: { name: "dastak:deployment-id", content: provenance.deploymentId }, injectTo: "head" },
            ],
          };
        },
      },
    }],
    build: {
      rollupOptions: {
        output: {
          manualChunks: {
            "icons-vendor": ["lucide-react"],
            "phone-vendor": ["libphonenumber-js"],
            "react-vendor": ["react", "react-dom"],
            "supabase-vendor": ["@supabase/supabase-js"],
          },
        },
      },
    },
    test: {
      environment: "node",
    },
  };
});
