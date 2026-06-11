# MWall

MWall is a native macOS menu bar wallpaper app with Noctalia-style terminal theme generation.

## Run

```sh
swift run mwall
```

The app runs as a menu bar utility and hides its Dock icon.

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
- Unsplash random landscape download with query, cache, and cache cleanup.
- Apply to current screen or all screens.
- Favorites and recent wallpaper history.
- Palette extraction from the applied wallpaper.
- Terminal theme output for Kitty, Alacritty, WezTerm, Ghostty, iTerm2, and Terminal.app helper script.
- Best-effort terminal reload hooks for Kitty, WezTerm, iTerm2 import, and Terminal.app.
- Launch at Login toggle when running as `MWall.app`.

## Unsplash

MWall uses the official Unsplash JSON API. Add your Unsplash Access Key in the popover before fetching. Demo apps are rate-limited by Unsplash, so cached downloads are kept under `~/Library/Caches/MWall/Unsplash`.

## Generated Theme Files

- Kitty: `~/.config/kitty/themes/mwall.conf`
- Alacritty: `~/.config/alacritty/themes/mwall.toml`
- WezTerm: `~/.config/wezterm/colors/mwall.toml`
- Ghostty: `~/.config/ghostty/themes/mwall`
- iTerm2: `~/Library/Application Support/MWall/MWall.itermcolors`
- Terminal.app helper: `~/Library/Application Support/MWall/Apply-MWall-Terminal.applescript`

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
theme = mwall
```
