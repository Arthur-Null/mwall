# Wallpaper palette prototype

Compare the production generator, unmodified Aether CLI palettes, and three experimental MWall palettes using cached Unsplash originals. The preview never writes MWall settings, active themes, or wallpapers.

## Build the preview

```sh
swiftc -O Sources/MWall/PaletteGenerator.swift \
  tools/palette-preview/PerceptualPalette.swift \
  tools/palette-preview/AetherReference.swift \
  tools/palette-preview/main.swift \
  -o /tmp/mwall-palette-preview-generator

/tmp/mwall-palette-preview-generator \
  "$HOME/Library/Caches/MWall/Unsplash" \
  tools/palette-preview/template.html /tmp/mwall-palette-preview/index.html \
  /tmp/mwall-palette-preview/aether-reference.json

```

The final argument is optional. With it, the preview includes five generators, dark/light variants, and Aether provenance; without it, it includes the four MWall generators. HTML embeds images and palettes and opens offline. A neighboring JSON contains the same data.

## Generate the original Aether reference

Upstream is pinned to `f0ae849966cc038a21808170b21e07772cb3619c` in `aether/UPSTREAM_REVISION`. Run these commands from the MWall repository with Git, Go, and Ruby installed:


```sh
git clone https://github.com/omacom/aether.git /tmp/mwall-aether-upstream
git -C /tmp/mwall-aether-upstream checkout --detach \
  "$(cat tools/palette-preview/aether/UPSTREAM_REVISION)"
cp tools/palette-preview/aether/cli-main.go /tmp/mwall-aether-upstream/mwall_cli_main.go
(
  cd /tmp/mwall-aether-upstream
  go build -o /tmp/mwall-aether-cli mwall_cli_main.go templates.go
)
ruby tools/palette-preview/aether/export.rb \
  /tmp/mwall-aether-upstream /tmp/mwall-aether-cli \
  "$HOME/Library/Caches/MWall/Unsplash" \
  /tmp/mwall-palette-preview/aether-reference.json

```

The tiny launcher calls upstream's `cli.Run` with its embedded templates. It omits the desktop GUI and does not replace extraction, palette generation, normalization, role mapping, or templates. Upstream tracked source must remain unchanged.

For each original image, the exporter runs:

- `--extract-palette IMAGE --extract-mode normal --json`, with and without `--light-mode`.
- `--show-variables COLORS --json` to obtain official background, foreground, accent, cursor, selection and ANSI roles.
- `--preview-template kitty IMAGE --json` to cross-check all 16 colors and background/foreground against Aether's actual Kitty template.

The reference stores the exact RGB strings, rendered Kitty templates, commit, extraction mode, and image SHA-256 hashes. The Swift importer rejects changed images, malformed colors, missing variants, and inconsistent ANSI mappings. It does **not** run MWall's gamut, contrast, saturation or hue adjustments on Aether output. Aether's own normal-mode processing remains part of its result. The importer uses background for the unused cursor-text field because the CLI exposes no separate cursor-text role.

Aether accent and cursor are distinct and remain distinct in the preview. All columns use one common sample syntax mapping so that the color generation can be compared directly; the HTML is not an emulation of Aether's Neovim template or editor UI. Aether contrast is reported, not corrected. Image representative swatches come from the MWall experiment.

Aether may write its normal extraction cache under `~/.cache/aether` on the machine running the exporter. No theme-application command is invoked. The reference can be copied to a second machine with identical original images, where image hashes and imported colors are verified again.

## Experimental MWall pipeline

- Sample sRGB while preserving proportions, longest side 192 pixels.
- Deterministic OKLab K-means, up to 32 clusters and 10 iterations; choose a real sampled pixel nearest each centroid.
- Prefer clusters covering at least 0.8% of pixels; retain up to six accents balancing population, chroma, and hue diversity.
- Select background tint from image shadows/highlights. Assign ANSI slots only from supported image colors, reusing neighboring colors for missing hue families.
- Preserve hue while changing OKLCH lightness; reduce chroma to fit sRGB. Main text targets 7:1; syntax, cursor, muted text and selected text target 4.5:1 on their intended backgrounds.
- Faithful keeps extracted accent chroma; Soft uses 0.65x, Vivid 1.35x. Gamut and contrast corrections can reduce the differences.

These three variants are original MWall experiments, not equivalent Aether or Noctalia ports. ANSI red/green semantics can weaken in near-monochrome pictures; error/success/diff roles need a separate decision before production adoption. Low-chroma images intentionally stay muted. The generator's contrast threshold applies only to these experiments, not the production baseline or Aether. Contrast checks are not a guarantee for every application color pairing.

References: [OKLab transforms](https://bottosson.github.io/posts/oklab/), [pinned Aether source](https://github.com/omacom/aether/tree/f0ae849966cc038a21808170b21e07772cb3619c), [Noctalia custom schemes](https://github.com/noctalia-dev/noctalia/blob/main/src/theme/custom_schemes.cpp).

Keep on the preview branch until visual evaluation selects a direction. Production MWall is unchanged.

