# Thorium / Chromium Browser Optimization Flags

A curated reference guide of verified performance, Wayland, and GPU hardware acceleration flags for Thorium / Chromium on Linux.

---

## 1. Curated Flag List

| # | Flag ID (`chrome://flags`) | Feature Name | Setting | CLI Flag / Feature Parameter |
|---|----------------------------|--------------|---------|------------------------------|
| 1 | `#enable-native-gpu-memory-buffers` | Enable Native GPU Memory Buffers | **Enabled** | `--enable-native-gpu-memory-buffers` |
| 2 | `#enable-gpu-rasterization` | GPU rasterization | **Enabled** | `--enable-gpu-rasterization` |
| 3 | `#enable-zero-copy` | Zero-copy rasterizer | **Enabled** | `--enable-zero-copy` |
| 4 | `#ozone-platform-hint` | Preferred Ozone platform | **Wayland** | `--ozone-platform-hint=wayland` |
| 5 | `#wayland-text-input-v3` | Wayland text-input-v3 | **Enabled** | `WaylandTextInputV3` |
| 6 | `#wayland-linux-drm-syncobj` | Wayland linux-drm-syncobj explicit sync | **Enabled** | `WaylandLinuxDrmSyncobj` |
| 7 | `#enable-parallel-downloading` | Parallel downloading | **Enabled** | `ParallelDownloading` |
| 8 | `#service-worker-auto-preload` | ServiceWorkerAutoPreload | **Enabled** | `ServiceWorkerAutoPreload` |
| 9 | `#root-scrollbar-follows-browser-theme` | Make scrollbar follow theme | **Enabled** | `RootScrollbarFollowsBrowserTheme` |
| 10 | `#zero-copy-rbp-partial-raster-with-gpu-compositor` | Zero-copy partial raster with GPU compositor | **Enabled** | `ZeroCopyRBPPartialRasterWithGpuCompositor` |
| 11 | `#new-content-for-checkerboarded-scrolls` | Change scrolling scheduling to reduce checkerboarding | **Enabled** | `NewContentForCheckerboardedScrolls` |

---

## 2. Copy-Paste Flag Anchor Tags (`chrome://flags`)

```text
#enable-native-gpu-memory-buffers
#enable-gpu-rasterization
#enable-zero-copy
#ozone-platform-hint
#wayland-text-input-v3
#wayland-linux-drm-syncobj
#enable-parallel-downloading
#service-worker-auto-preload
#root-scrollbar-follows-browser-theme
#zero-copy-rbp-partial-raster-with-gpu-compositor
#new-content-for-checkerboarded-scrolls
```

---
