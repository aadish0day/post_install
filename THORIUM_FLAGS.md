# Thorium / Chromium Browser Optimization Flags

A curated reference guide of verified performance, Wayland, and GPU hardware acceleration flags for Thorium / Chromium on Linux.

---

## 1. Verified Working Flags (`~/.config/thorium/thorium-flags.conf`)

For AMD Radeon (RDNA2/Rembrandt 680M / Mesa / Wayland):

```text
--disable-features=ExtensionManifestV2DeprecationWarning,ExtensionManifestV2Unsupported,ExtensionManifestV2Disabled,WaylandLinuxDrmSyncobj
--enable-features=AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks,VaapiVideoEncoder
--ignore-gpu-blocklist
--enable-gpu-rasterization
--ozone-platform-hint=auto
```

> [!IMPORTANT]
> **Why `WaylandLinuxDrmSyncobj`, `AcceleratedVideoDecodeLinuxZeroCopyGL`, `--enable-zero-copy`, and `--enable-native-gpu-memory-buffers` MUST be disabled on KDE Wayland:**
> 1. `WaylandLinuxDrmSyncobj` causes a fatal client crash (`wp_linux_drm_syncobj_surface_v1: error 2: only linux dmabuf buffers are allowed to use explicit sync`) because KWin terminates the connection when non-dmabuf surfaces are presented.
> 2. `AcceleratedVideoDecodeLinuxZeroCopyGL` and `--enable-zero-copy` cause `eglCreateImage failed with 0x00003009 (EGL_BAD_MATCH)` and `OzoneImageBacking::ProduceSkiaGanesh failed to create GL representation`, causing audio to play while video stays black/frozen and the browser stutters/clicks in an endless loop.



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
