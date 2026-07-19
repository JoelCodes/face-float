# FaceFloat — FaceScreen clone for macOS

## Goal

A floating, always-on-top webcam overlay for macOS, like facescreenapp.com: resizable,
circle or rectangle shaped, with optional person segmentation that removes or blurs
everything behind the user.

## Decisions (confirmed with Joel, 2026-07-18)

- Cutout styles: **both** fully-transparent cutout and background blur, toggleable.
- Controls: **both** a menu bar icon and a right-click context menu on the window.
- Distribution: personal use, built locally. Ad-hoc signing only.

## Stack

Native Swift (AppKit + AVFoundation + Vision + Core Image + Metal), built with Swift
Package Manager. A small script assembles the binary into `FaceFloat.app` so macOS
attributes the camera permission to the app rather than the terminal.

## Architecture

- **`main.swift` / `AppDelegate`** — accessory-policy app (no Dock icon), wires all
  components, owns menu actions and settings.
- **`OverlayWindow`** — borderless + resizable, transparent, `level = .floating`,
  joins all Spaces, movable by background. Circle shape locks a 1:1 content aspect
  ratio; rectangle is freeform. Frame autosaved.
- **`CameraManager`** — `AVCaptureSession` with `AVCaptureVideoDataOutput` (BGRA,
  late frames discarded) on a serial queue. Device discovery covers built-in,
  external, and Continuity cameras. Handles hot-unplug by falling back to the
  default camera.
- **`FrameProcessor`** — per-frame pipeline on the capture queue:
  1. `VNGeneratePersonSegmentationRequest` (`.balanced`, one-component-8 mask) when
     mode ≠ normal.
  2. `CIBlendWithMask` composites the person over either a clear background
     (cutout) or a Gaussian-blurred copy of the frame (blur).
  3. Optional horizontal mirror.
  Note: this is person-shape segmentation, not literal depth sensing — webcams have
  no depth sensor — but it delivers the "keep me, cut the rest" effect.
- **`VideoView`** — `MTKView` + `CIContext` rendering, draw-on-demand. Clears to
  transparent each frame so cutout mode shows the desktop through the window.
  Aspect-fill with center crop. Shape is a `cornerRadius` mask on the Metal layer
  (radius = min(w,h)/2 for circle, 16pt for rectangle).
- **Menus** — one builder populates both the status-item menu and the window's
  context menu (via `NSMenuDelegate.menuNeedsUpdate`): camera picker, shape, mode,
  mirror, size presets, quit.
- **`Settings`** — `UserDefaults`-backed shape, mode, mirror, and camera ID.

## Error handling

- Camera permission denied → alert with a button that deep-links to
  System Settings → Privacy → Camera.
- Selected camera disappears → fall back to system default, rebuild menu state.
- Segmentation failure on a frame → fall back to the raw frame for that frame.

## Build & run

```sh
./scripts/make-app.sh   # swift build -c release + assemble + ad-hoc codesign
open build/FaceFloat.app
```

## Testing

GUI/camera behavior is verified manually (window drag/resize, each mode, each
shape, camera switching). Logic worth unit-testing is minimal by design.
