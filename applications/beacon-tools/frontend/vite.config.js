import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3011,
    allowedHosts: ["tools.beacon.famillelallier.net"],
    proxy: {
      "/api/minio": {
        target: "http://beacon-tools-minio:8000",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api\/minio\/?/, "/"),
      },
    },
  },
});
