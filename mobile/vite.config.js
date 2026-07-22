import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import { VitePWA } from "vite-plugin-pwa";

// PAGES_BASE is NOT cosmetic. On a GitHub Pages *project* site the app is served from /<repo>/. With a
// relative base the service worker gets an invalid scope: the app installs but never works offline —
// while looking fine on the first visit. CI sets it; local `vite preview` keeps the relative one.
export default defineConfig({
  base: process.env.PAGES_BASE || "./",
  plugins: [
    svelte(),
    VitePWA({
      registerType: "autoUpdate", // skipWaiting + clientsClaim: a push reaches phones on next launch
      manifest: {
        name: "Nidus Capture",
        short_name: "Nidus",
        description: "Capture ideas and tasks into your Nidus projects while away from your computer.",
        start_url: "./",
        scope: "./",
        display: "standalone",
        background_color: "#141519",
        theme_color: "#141519",
        icons: [
          { src: "icon-192.png", sizes: "192x192", type: "image/png" },
          { src: "icon-512.png", sizes: "512x512", type: "image/png" },
          { src: "icon-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
        ],
      },
      workbox: { globPatterns: ["**/*.{js,css,html,png,svg,ico}"] },
    }),
  ],
});
