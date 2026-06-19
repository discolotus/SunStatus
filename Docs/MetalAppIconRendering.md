# Metal App Icon Rendering

This branch prototypes a GPU-generated app icon source.

Run:

```sh
swift run SunStatusIconRenderer
```

The renderer compiles an inline Metal compute shader and writes:

- `Assets/AppIconMetal.png`: the generated 1024 px app icon source.
- `screenshots/pr-evidence/metal-app-icon-comparison.png`: current PNG source
  beside the Metal-rendered source.

The Xcode `Generate App Icon` build phase uses `Assets/AppIconMetal.png` on
this branch, then downscales it into the `.iconset` sizes and builds
`AppIcon.icns` the same way the current static PNG source does.

Initial visual read: the Metal source has deterministic vector-like edges and
transparent icon corners, but it is flatter than the current image-generated PNG.
The comparison screenshot is intended as the main review artifact before deciding
whether to refine this shader further or keep the existing app icon.
