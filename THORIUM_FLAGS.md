# Thorium / Chromium Browser Optimization Flags

A curated reference guide of verified performance, Wayland, and GPU hardware acceleration flags for Thorium / Chromium on Linux.

---

## 1. Verified Working Flags (`~/.config/thorium/thorium-flags.conf`)

For AMD Advantage Laptops (Dual AMD GPUs: Radeon 680M iGPU + RX 6700S dGPU / Mesa / Wayland):

```text
--disable-features=ExtensionManifestV2DeprecationWarning,ExtensionManifestV2Unsupported,ExtensionManifestV2Disabled,WaylandLinuxDrmSyncobj
--enable-features=AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks,VaapiVideoEncoder,AutomaticTabDiscarding,HighEfficiencyModeAvailable
--enable-gpu-rasterization
--ignore-gpu-blocklist
--render-node-override=/dev/dri/renderD129
--process-per-site
--renderer-process-limit=8
```

> [!IMPORTANT]
> **Key Technical Fixes:**
> 1. **`--render-node-override=/dev/dri/renderD129`:**
>    On dual-GPU laptops (e.g. ASUS ROG Zephyrus G14), the desktop display is handled by the Integrated Radeon 680M (`renderD129`), but Chromium's VA-API scanner defaults to the first DRM device (`renderD128` - discrete RX 6700S). Attempting to import video buffers across the two GPUs causes `nullptr returned from gbm_bo_import`, crashing the GPU process 3 times and disabling hardware acceleration (falling back to software SwiftShader). Overriding the render node directly to `/dev/dri/renderD129` resolves this completely.
> 2. **`AcceleratedVideoDecodeLinuxGL`:**
>    Enables VA-API hardware decoding via GL textures, allowing hardware AV1/VP9/HEVC/H.264 playback on the Radeon 680M and eliminating the 15 software `dav1d-worker` CPU threads that cause 80°C overheating.
> 3. **Avoid `WaylandLinuxDrmSyncobj` & `--enable-zero-copy`:**
>    - `WaylandLinuxDrmSyncobj` triggers a fatal KWin Wayland explicit sync protocol error (`wp_linux_drm_syncobj_surface_v1 error 2: only linux dmabuf buffers are allowed to use explicit sync`), crashing the browser immediately.
>    - `--enable-zero-copy` triggers `eglCreateImage 0x3009 (EGL_BAD_MATCH)` on Wayland with ANGLE, causing black video screens with audio clicking loops.
> 4. **`--process-per-site` & `--renderer-process-limit=8` (Process & Memory Consolidation):**
>    By default, Chromium allocates an independent 300–500 MB renderer process for every open tab, quickly exhausting 16 GB systems. `--process-per-site` groups tabs from the same domain into a single shared renderer, and `--renderer-process-limit=8` sets a hard ceiling on concurrent web processes, reducing active browser RAM consumption by over 50–60% (e.g., from ~6.3 GB down to ~2.3 GB) without sacrificing stability.
> 5. **`AutomaticTabDiscarding,HighEfficiencyModeAvailable` (Tab Hibernation):**
>    Enables aggressive background tab hibernation. Stale, inactive tabs are frozen and discarded from RAM until clicked again, freeing up gigabytes of memory while preserving complete tab and session state.
