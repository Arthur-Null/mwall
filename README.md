# MWall

MWall is a native macOS menu bar wallpaper app with four wallpaper-derived palette styles and live theme exports.

## Run

```sh
tools/build_aether.sh
swift run mwall
```

The app runs as a menu bar utility and hides its Dock icon.

When "all desktops" is enabled, MWall updates the macOS wallpaper store so hidden Spaces pick up the same image, then refreshes visible displays through `NSWorkspace`. Older macOS versions may fall back to System Events and ask for automation permission.

Applied wallpapers are copied to unique files under `~/Library/Application Support/MWall/Applied/` before being written into the system wallpaper index. Unique paths force a desktop refresh on each apply and protect the live image from Unsplash cache cleanup. The index keeps `Files` empty: the `[{ relative = ... }]` shape suggested by older docs stops WallpaperAgent from loading the image on current macOS.

## Build an App Bundle

```sh
tools/package_app.sh
open dist/MWall.app
```

The packaging script creates `dist/MWall.app`, sets `LSUIElement` so it behaves like a menu bar utility, and ad-hoc signs the app. The default bundle is intentionally not sandboxed because MWall writes terminal theme files under `~/.config`.

For future sandbox testing only:

```sh
MWALL_SANDBOX=1 tools/package_app.sh
```

## Features

- Menu bar popover for browsing wallpapers.
- Built-in fallback wallpapers generated on first launch.
- Local wallpaper folders.
- Security-scoped bookmarks for user-selected folders, ready for sandboxed builds.
- Unsplash featured wallpaper pool with preview/full-resolution two-layer cache.
- Wallhaven keyword search, categories, sorting, and pagination, defaulting to SFW anime wallpapers.
- Apply to the current desktop or all macOS desktops/Spaces.
- Favorites and recent wallpaper history.
- Dark and light palette extraction from the applied wallpaper.
- Terminal theme output for Kitty, Alacritty, WezTerm, Ghostty, iTerm2, and Terminal.app helper script.
- Best-effort terminal reload hooks for Kitty, WezTerm, iTerm2 import, and Terminal.app.
- Neovim colorschemes with live updates for open editors, including AstroNvim and LazyVim.
- Pi themes with native live updates, plus Codex CLI syntax-highlighting themes.
- Opt-in Codex App synchronization of light and dark desktop palettes, applied on app restart.
- Launch at Login toggle when running as `MWall.app`.

## Palette styles and interface

The menu bar panel has three pages: **壁纸** for browsing, **配色** for choosing a generation style and previewing code, and **设置** for app targets, automation, folders, and online sources.

- **Aether** uses the upstream normal-mode generator at commit f0ae849966cc038a21808170b21e07772cb3619c, without MWall recoloring. HEIC and TIFF inputs are decoded by macOS into a temporary sRGB PNG because upstream does not decode those formats; JPEG, PNG, GIF and WebP inputs within upstream limits pass through unchanged. Native-format inputs and images exceeding the upstream 16,384-pixel dimension or 40-megapixel limit are imported at up to 4,096 pixels on the longest side, preserving aspect ratio.
- **忠实壁纸** (default) keeps wallpaper hues with a light tinted background (OKLab chroma ≤ ~0.012).
- **柔和** follows Noctalia muted-style surfaces: near-neutral light backgrounds (chroma ≤ ~0.008) and quieter accents.
- **鲜艳** raises accent chroma; light backgrounds stay more restrained than before.

The former single-seed/fixed-hue generator has been removed. Existing settings migrate to **忠实壁纸** while keeping target apps and other preferences. Style changes update the preview without writing theme files. **生成并应用**, Codex App copying, and automatic generation after wallpaper changes all use the saved style.

Each style generates both light and dark palettes. Previewing online wallpapers uses a cached original when present; otherwise the interface labels the thumbnail preview. Applying downloads or reuses the original before extracting colors. Generation runs off the UI thread. Cached results are keyed by image path, modification time, size, and style.

The three MWall styles use aspect-preserving sRGB sampling and OKLab clustering with real-pixel representatives. They target 7:1 main-text contrast and 4.5:1 ANSI accent contrast against the background. These checks do not guarantee that every syntax role is visually distinct. Missing wallpaper hues can also weaken conventional ANSI red/green semantics. Aether keeps its own contrast and hue decisions.

### Aether build dependency

tools/build_aether.sh fetches a pinned upstream checkout into .build/aether-source and builds a small launcher into Aether's unchanged CLI. Go is needed only when building the helper; Go's toolchain download may run on the first build. The packaged MWall.app includes the executable and needs neither a separate Aether installation nor Go at runtime.

No theme-application command is invoked in Aether. Extraction can use its standard cache under ~/.cache/aether/color-cache. For development and tests only, MWALL_AETHER_BIN can specify an explicit helper path. The source revision is recorded in tools/aether/UPSTREAM_REVISION.

### Visual verification

Render the real SwiftUI view with isolated fixture state, without changing settings, wallpaper, or themes:

    "$(swift build --show-bin-path)/mwall" --snapshot-ui /tmp/mwall-palette.png \
      "$HOME/Library/Caches/MWall/Unsplash" 540 740 配色 light faithful

The page can be 壁纸, 配色, or 设置; appearance can be light or dark. Minimum supported content size is 440 by 620 points. Fixture input uses the local cache's metadata.json and Full/ originals. Generated captures are QA artifacts, not mockups.

To verify that production output matches the reviewed comparison JSON:

    MWALL_PALETTE_REFERENCE=/path/to/palette-preview/index.json \
    MWALL_PALETTE_CACHE="$HOME/Library/Caches/MWall/Unsplash" swift test -c release

## Unsplash

MWall uses the official Unsplash JSON API. Add your Unsplash Access Key in the popover, then switch to the Unsplash source or click "换一批" to fill the featured wallpaper pool.

Unsplash API JSON requests are rate-limited by Unsplash, while image file requests from `images.unsplash.com` are not counted as API requests. MWall therefore keeps a local two-layer cache under `~/Library/Caches/MWall/Unsplash`:

- `Previews/`: 600x338 preview images used by the wallpaper grid.
- `Full/`: 3840x2160 images downloaded only when a wallpaper is applied.
- `metadata.json`: cached Unsplash photo metadata and local file paths.

## Wallhaven

Select **Wallhaven** in the wallpaper source picker. The default search shows SFW anime wallpapers in landscape orientation at 1920x1080 or higher. Search by keyword or tag, switch between anime/general/people/all categories, and sort randomly, by newest, or by the monthly toplist. Pagination preserves the random seed; **换一批** starts a new random sequence.

An API key is optional. Under **设置 → Wallhaven**, paste a key from your Wallhaven account settings and click **保存**. MWall stores it in macOS Keychain, sends it only in the API request's `X-API-Key` header, and never includes it in settings JSON, search URLs, image requests, or cache metadata. **移除密钥** returns to anonymous access. Both modes explicitly request SFW content rather than inheriting account purity defaults.

Wallhaven's official API documentation lists 45 API calls per minute without specifying a higher authenticated quota. MWall does not promise a rate-limit increase for configured keys. Invalid keys and rate limiting produce separate messages; failed searches preserve the previous cached page.

Wallhaven uses its own cache under `~/Library/Caches/MWall/Wallhaven`: `Previews/` holds thumbnails, `Full/` holds originals in their original file format, and `metadata.json` records the last successful search page without credentials. Originals download on demand when applying wallpapers or generating themes. Favorites and history retain the provider identity even when displayed under another source. Each provider has an independent cache limit.

The integration references the [Noctalia Wallhaven plugin](https://github.com/noctalia-dev/official-plugins/tree/main/wallhaven) and the [official Wallhaven API](https://wallhaven.cc/help/api). It uses native Swift and SwiftUI rather than importing the plugin runtime.

For an opt-in anonymous network check, run `MWALL_WALLHAVEN_LIVE=/tmp/mwall-wallhaven-live swift test --filter wallhavenLiveSmoke`. This downloads one page of SFW previews and one original into the specified test directory, without applying wallpapers or changing settings. That directory also works as `--snapshot-ui` fixture input for Wallhaven's default search.

## Codex App Synchronization

Enable **Codex App** under **设置 → 同步到应用**, then generate a theme or change wallpaper with theme generation enabled. This target is opt-in, including on new installations. MWall automatically writes both wallpaper-derived light and dark desktop palettes to the user's Codex configuration; copying and importing a theme string is no longer required.

The colors take effect the next time the desktop app starts. A running app keeps its theme in memory, so MWall reports **重启 App 后生效** and does not restart the app. The existing **复制 Codex App** button remains available for manual import into a running app or older versions.

Synchronization requires a recent Codex App or Codex CLI with the desktop settings in the **desktop** section of **config.toml**. Codex CLI 0.154.0 was validated. MWall discovers the bundled CLI in ChatGPT.app / Codex.app, Homebrew, common user binary directories, or its process PATH. It honors CODEX_HOME, otherwise using ~/.codex/config.toml. It uses the official app-server **config/read** and **config/batchWrite** APIs to preserve TOML and update both variants atomically, with a version check to reject concurrent edits. It changes accent, background, foreground, and semantic diff/skill colors while preserving fonts, contrast, transparency, appearance mode, code themes, and unrelated configuration. Missing theme fields receive valid defaults. Identical palettes do not rewrite the file.

Missing CLI binaries, incompatible versions, invalid configuration, conflicts, and timeouts are reported without preventing other selected theme exports. Synchronization runs off the UI thread and makes no model requests. Reference: [Codex app-server configuration APIs](https://developers.openai.com/codex/app-server/).

For an isolated integration test against an installed CLI, run **MWALL_CODEX_CLI=/opt/homebrew/bin/codex swift test**. The test uses temporary configurations, preserves unrelated preferences, exercises repeat updates and version conflicts, and never changes the user's Codex configuration.

## Generated Theme Files

- Kitty: `~/.config/kitty/themes/mwall.conf`, `mwall-dark.conf`, `mwall-light.conf`
- Alacritty: `~/.config/alacritty/themes/mwall.toml`, `mwall-dark.toml`, `mwall-light.toml`
- WezTerm: `~/.config/wezterm/colors/mwall.toml`, `mwall-dark.toml`, `mwall-light.toml`
- Ghostty: `~/.config/ghostty/themes/mwall`, `mwall-dark`, `mwall-light`
- iTerm2: `~/Library/Application Support/MWall/MWall.itermcolors`, `MWall Dark.itermcolors`, `MWall Light.itermcolors`
- Terminal.app helper: `~/Library/Application Support/MWall/Apply-MWall-Terminal.applescript`, plus dark/light variants
- Neovim: `~/.config/nvim/colors/mwall.lua`, `mwall-dark.lua`, `mwall-light.lua`
- Neovim live reload: `~/.config/nvim/plugin/mwall-reload.lua`
- Pi: `~/.pi/agent/themes/mwall.json`, `mwall-dark.json`, `mwall-light.json`
- Codex CLI: `~/.codex/themes/mwall.tmTheme`, `mwall-dark.tmTheme`, `mwall-light.tmTheme`

Most terminals need their main config to import the generated theme file, or a manual import in the app UI.

## Terminal Imports

Kitty:

```conf
include themes/mwall.conf
```

Alacritty:

```toml
import = ["~/.config/alacritty/themes/mwall.toml"]
```

WezTerm:

```lua
config.color_scheme_dirs = { os.getenv("HOME") .. "/.config/wezterm/colors" }
config.color_scheme = "mwall"
```

Ghostty:

```conf
theme = dark:mwall-dark,light:mwall-light
```

For terminals that do not have automatic light/dark theme switching, `mwall.conf` / `mwall.toml` / `mwall` is regenerated from the current macOS appearance when MWall writes themes.

## Neovim Live Themes

Enable the Neovim target and generate a theme in MWall, then select `mwall` in your editor configuration:

```lua
-- Plain Neovim
vim.cmd.colorscheme("mwall")
```

For AstroNvim, set `colorscheme = "mwall"` in your `AstroNvim/astroui` options. For LazyVim, set it in your `LazyVim/LazyVim` options. MWall writes its own colors and runtime plugin files; it does not edit your plugin specifications or `init.lua`.

The runtime plugin checks the active MWall colorscheme file every second. When MWall regenerates it, each open Neovim reloads that scheme and redraws automatically, even without a focus change. Atomic file replacement is supported. `ColorScheme` callbacks run normally so plugin UI updates and user highlight/transparency overrides are reapplied. Rewriting identical content does not trigger a reload, and selecting an unrelated colorscheme suspends MWall updates.

### First activation in an already-open editor

After generating themes with this version of MWall, run this once in editors opened before the reload plugin was installed:

```vim
:runtime plugin/mwall-reload.lua
```

This activates live updates without restarting Neovim. New sessions and subsequent selections of a generated MWall scheme load the plugin automatically. Future wallpaper/theme updates need no manual command.

### Light and dark variants

`mwall` reflects the macOS appearance at the time MWall generates themes. MWall does not currently regenerate files merely because macOS changes appearance. To follow appearance changes independently, keep your existing `auto-dark-mode.nvim` integration:

```lua
{
  "f-person/auto-dark-mode.nvim",
  opts = {
    set_dark_mode = function() vim.cmd.colorscheme("mwall-dark") end,
    set_light_mode = function() vim.cmd.colorscheme("mwall-light") end,
    fallback = "dark",
  },
}
```

Live updates preserve whichever variant is active. They do not depend on the terminal reload setting. Set `vim.g.mwall_auto_reload = false` to disable Neovim live updates.

### Verification

Run `swift test` with Neovim installed (or set `NVIM_BIN` to its executable). The integration test uses isolated temporary configs and a single running Neovim to verify all three generated schemes, atomic replacements, unchanged files, highlight overrides, unsaved buffers, invalid-file recovery, and opt-out behavior. It does not change your editor configuration.

## Pi and Codex CLI

Enable **Pi** and/or **Codex CLI** in MWall, then click **生成主题** or apply a wallpaper with theme generation enabled. Existing saved target selections are preserved, so existing installations must enable the new targets once. New settings include both targets by default.

Both exporters write `mwall`, `mwall-dark`, and `mwall-light`. The `mwall` variant uses macOS appearance when generated. Unchanged theme content is left untouched. The Pi and Codex CLI exporters do not edit settings or automatically select a theme. The separate Codex App target updates desktop palette settings as described above.

### Pi

In Pi's `/settings`, select `mwall` once. Pi's native file watcher then reloads regenerated themes in running sessions, including atomic replacements, without a restart or manual reload. Interface accents, message/tool panels, Markdown, syntax highlighting, and diff colors share the wallpaper palette. The base terminal background continues to come from the terminal; enable MWall's matching terminal output as well.

To follow the terminal's light/dark appearance, select the pair in Pi settings or start with:

```sh
pi --use-theme mwall-light/mwall-dark
```

Pi detects the terminal's appearance; this is not a macOS theme scheduler. Both palette variants are refreshed whenever MWall generates themes.

### Codex CLI

In Codex CLI, run `/theme` and select `mwall`, `mwall-dark`, or `mwall-light`. The selection is saved as `tui.theme`. These TextMate themes apply to syntax highlighting in code blocks and diffs. They are separate from the desktop application's **复制 Codex App** import string and do not customize every TUI element.

Codex CLI 0.154.0 was verified to load and preview these generated themes, but it caches loaded themes: after externally replacing a theme file, reopening `/theme` still showed the previous palette. Start a new Codex CLI session to reliably pick up regenerated colors. `/theme` can switch the available variants without restarting; automatic file reload and Pi-style light/dark pairing are not provided by this exporter.

### Custom locations and validation

The exporters honor `PI_CODING_AGENT_DIR` and `CODEX_HOME` when these environment variables are present in the MWall process. A Finder-launched app does not normally inherit shell-only variables; otherwise the default paths above are used.

`swift test` checks serialization, palette mapping, preserved settings, directory overrides, and unchanged-file handling. To additionally exercise the installed Pi theme loader and watcher, set `PI_PACKAGE_DIR` to the root of an installed `@earendil-works/pi-coding-agent` package:

```sh
PI_PACKAGE_DIR="$(npm root -g)/@earendil-works/pi-coding-agent" swift test
```

The Pi integration test uses temporary themes and does not change running user sessions. It covers all three variants, repeated atomic replacements, invalid-file recovery, and light/dark pair resolution. Reference interfaces: [Pi themes](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/themes.md) and [Codex CLI customization](https://developers.openai.com/zh-Hans/docs/cli-customization).
