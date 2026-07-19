# FaceFloat

A native macOS clone of [FaceScreen](https://facescreenapp.com/): a floating,
always-on-top webcam overlay for screen recordings and presentations.

## Features

- Borderless, transparent, always-on-top camera window — drag anywhere to move,
  drag edges/corners to resize
- **Circle** (aspect-locked) or **rectangle** (freeform, rounded) shape
- **Cutout mode** — Apple Vision person segmentation makes the background fully
  transparent, so you float directly over your desktop
- **Blur mode** — portrait-style background blur
- Camera picker (built-in, external, Continuity Camera), mirror toggle, size presets
- Controls in both the menu bar icon and the window's right-click menu
- Remembers shape, mode, mirror, camera, and window position across launches

## Build & run

```sh
./scripts/make-app.sh
open build/FaceFloat.app
```

Requires macOS 14+ and the Swift toolchain (Xcode or Command Line Tools).
On first launch, approve the camera permission prompt.

The app has no Dock icon — look for the camera icon in the menu bar. Quit from
either menu.

## How segmentation works

`VNGeneratePersonSegmentationRequest` produces a per-frame person mask on the
Neural Engine; Core Image blends the camera frame over a transparent (cutout) or
blurred (blur) background, rendered through Metal for smooth playback. This is
person-shape segmentation rather than true depth sensing — webcams have no depth
sensor — but it gives the "keep me, cut the rest" effect.
