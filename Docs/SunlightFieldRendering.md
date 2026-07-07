# Sunlight Field Rendering

The dynamic daylight widget needs a smooth field that changes by both time of day
and cloud cover. The current Canvas-only approach is fragile when it builds that
field from many translucent strokes or wedge fills: overlapping alpha can create
visible seams, banding, and unexpected dark regions.

## Options Considered

- **Single-pass Core Graphics texture**: Generate one small bitmap for the
  sunlight field, assigning each pixel its final color from polar position,
  daylight progress, brightness, and cloud cover. Draw that image once and keep
  Canvas for the crisp foreground arc, cloud ring, boundary lines, and sun.
  This is the preferred production path because it works with the current
  macOS 14 target, is deterministic in Xcode previews and WidgetKit, and avoids
  overlap artifacts by construction.
- **SwiftUI Metal shader**: Use a `Shader`/`layerEffect` or Canvas shader to
  compute the same polar field on the GPU. This is the cleanest mathematical
  model and should remain a prototype candidate, especially for future richer
  animation. It is not the first production move because widget extension and
  preview behavior with bundled Metal functions need more verification.
- **SwiftUI MeshGradient**: Useful for liquid-glass color blending, but not a
  stable baseline for this app while the package targets macOS 14. It also does
  not solve the cloud-layer cutoff without additional masks.
- **More Canvas bands or compositing groups**: These can reduce artifacts but do
  not remove the root problem. Multiple translucent passes can still accumulate
  color at joins and antialiased edges.

## Chosen Direction

Use a single-pass texture for the daylight background field. The renderer maps
pixels into arc-relative polar coordinates, ignores pixels outside the daylight
sector, keeps the area below the sunrise/sunset boundary transparent, and applies
cloud occlusion only below the cloud layer. Foreground strokes remain vector
Canvas drawing so the widget keeps sharp liquid-glass edges.
