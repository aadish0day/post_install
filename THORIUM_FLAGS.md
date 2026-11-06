# Thorium / Chromium Browser Optimization Flags

A curated reference guide of verified performance, Wayland, and GPU hardware acceleration flags for Thorium / Chromium on Linux.

---

## 1. Verified Working Flags (`~/.config/thorium/thorium-flags.conf`)

For AMD Radeon (RDNA2/Rembrandt 680M / Mesa / Wayland):

```text
--disable-features=ExtensionManifestV2DeprecationWarning,ExtensionManifestV2Unsupported,ExtensionManifestV2Disabled
--enable-features=AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks,VaapiVideoEncoder,WaylandLinuxDrmSyncobj,WaylandTextInputV3
--ignore-gpu-blocklist
--enable-gpu-rasterization
--ozone-platform-hint=wayland
```

> [!IMPORTANT]
> **Do NOT use `AcceleratedVideoDecodeLinuxZeroCopyGL`, `--enable-zero-copy`, or `--enable-native-gpu-memory-buffers` on Wayland with Mesa/ANGLE.**
> They trigger `eglCreateImage failed with 0x00003009 (EGL_BAD_MATCH)` and `OzoneImageBacking::ProduceSkiaGanesh failed to create GL representation`, which causes audio to play while the video screen stays black or frozen, and creates an endless error loop that lags the browser.


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
