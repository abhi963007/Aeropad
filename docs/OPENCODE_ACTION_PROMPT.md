# AeroPad Master Engineering Directive: Architecture Analysis & Optimization

Analyze `@RESEARCH_AND_ARCHITECTURE.md` and `@assets/ui.png`. Your objective is to resolve all performance and connectivity bottlenecks across the mobile client (`lib/main.dart`) and desktop receiver (`server/aeropad_server.py`) to deliver a production-ready, ultra-smooth 120 FPS wireless trackpad.

---

### 🔍 1. Architecture Context & Goals
Review sections 3, 4, 6, 8, and 12 of `RESEARCH_AND_ARCHITECTURE.md`:
- Target end-to-end glass-to-cursor latency: **$\le 12\text{ ms}$**.
- Motion rendering performance: **Locked 60–120 FPS** with zero CPU frame drops.
- Connectivity: **Zero-configuration auto-connect** over Windows Laptop Hotspot (`192.168.137.1`), Phone Hotspot (`192.168.43.1`), and Local Wi-Fi.

---

### ⚡ 2. Immediate Action Item A: Fix Animation Stutter & Lag (`lib/main.dart`)

The current `_ParticleLatticePainter` stutters because it executes over 1 million transcendental math operations (`pow`, `exp`, `sin`, `sqrt`) per second on the UI thread (1,000+ dots × up to 18 ripples on every frame).

Apply these optimizations:
1. **Throttle Drag Waves:**
   - Do **NOT** call `_addRipple()` inside `onPointerMove`. Instead, store a single active touch point `_currentTouch = event.localPosition`.
   - Only trigger expanding ripples on `onPointerDown` and `onPointerUp` (taps/clicks).
   - Cap maximum concurrent ripples to **3**, and reduce ripple duration from `3.2s` to **`0.85s`**.

2. **Distance Culling (Early Exit):**
   - For every particle, compute fast squared distance or difference to wave radius:
     ```dart
     final waveRadius = 320.0 * age;
     final diff = distance - waveRadius;
     if (diff.abs() > 70.0) continue; // Outside active wave band -> skip exp/sin completely!
     ```
   - This eliminates calculations for 90% of unaffected dots on every frame.

3. **Fast Arithmetic:**
   - Replace `math.pow(diff, 2)` with `diff * diff`.
   - Batch-render resting background dots (`#146B8A`, opacity `0.25`) with a single static `Paint`.

4. **Instant Touch Illumination:**
   - When `_currentTouch != null`, illuminate nearby particles (radius $\le 50\text{px}$) to vivid electric cyan (`#00D9FF`) for zero-latency visual feedback directly under the gliding finger.

---

### 📶 3. Immediate Action Item B: Flawless Hotspot & Wi-Fi Auto-Discovery

1. **Active Gateway Probing (`lib/main.dart`):**
   - In `NetworkMouseClient.discover()`, actively probe:
     - `192.168.137.1` (Windows Mobile Hotspot default gateway)
     - `192.168.43.1` (Android Hotspot default gateway)
     - `127.0.0.1` (USB ADB forward `adb forward tcp:8989 tcp:8989`)
     - `255.255.255.255` (Subnet broadcast)
   - In `_handleDiscovery`, **always set `address = sourceAddress`** (the real UDP socket sender) instead of `packet['ip']` to avoid virtual adapter mismatches (WSL/Hyper-V).

2. **Server Discovery Responder (`server/aeropad_server.py`):**
   - When a discovery request is received on port `8988`, respond immediately to `address` on the sender's incoming interface.
   - Display the active laptop hotspot IP (`192.168.137.1`) in the console startup banner.

---

### 🎨 4. UI & Ergonomics
- Preserve the exact clean minimalist aesthetic of `assets/ui.png`.
- Ensure no guide text is shown in the middle of the touch surface.
- Keep the ultra-thin bezel padding (`11px` side margins).

---

### 🛠️ 5. Verification & Build
1. Format all code: `dart format .`
2. Run static analysis: `flutter analyze` (Must pass with 0 errors/warnings).
3. Build the APK: `flutter build apk --debug`.
4. Ensure `server/aeropad_server.py` is ready to run.
