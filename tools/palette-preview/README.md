# Wallpaper palette prototype

Compare the production generator with three experimental multi-color palettes using locally cached Unsplash originals. The tool never writes app settings, themes, or wallpapers.

```sh
swiftc -O Sources/MWall/PaletteGenerator.swift tools/palette-preview/PerceptualPalette.swift tools/palette-preview/main.swift -o /tmp/mwall-palette-preview-generator
/tmp/mwall-palette-preview-generator "$HOME/Library/Caches/MWall/Unsplash" tools/palette-preview/template.html /tmp/mwall-palette-preview/index.html
```

Output HTML embeds images and palettes and opens offline. A neighboring JSON contains the same data for inspection. Runtime diagnostics check color round trips and generated text contrast.

## Experimental pipeline

- Sample sRGB while preserving proportions, longest side 192 pixels.
- Deterministic OKLab K-means, up to 32 clusters and 10 iterations; choose a real sampled pixel nearest each centroid.
- Prefer clusters covering at least 0.8% of pixels; retain up to six accents balancing population, chroma, and hue diversity.
- Select background tint from image shadows/highlights. Assign ANSI slots only from supported image colors, reusing neighboring colors for missing hue families.
- Preserve hue while changing OKLCH lightness; reduce chroma to fit sRGB. Main text targets 7:1; syntax, cursor, muted text and selected text target 4.5:1 on their intended backgrounds.
- Faithful keeps extracted accent chroma; Soft uses 0.65x, Vivid 1.35x. Gamut and contrast corrections can reduce the differences.

This is an original MWall experiment inspired by Aether and Noctalia, not an equivalent port. ANSI red/green semantics can weaken in near-monochrome pictures; error/success/diff roles need a separate decision before production adoption. Low-chroma images intentionally stay muted. Contrast checks are not a guarantee for every application color pairing.

References: [OKLab public-domain transforms](https://bottosson.github.io/posts/oklab/), [Aether ANSI mapping](https://github.com/omacom/aether/blob/main/internal/extraction/palette_chromatic.go), [Noctalia custom schemes](https://github.com/noctalia-dev/noctalia/blob/main/src/theme/custom_schemes.cpp).

Keep on the preview branch until visual evaluation selects a direction. Production MWall is unchanged.

