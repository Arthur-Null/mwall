# MWall

MWall is a native macOS menu bar wallpaper app with Noctalia-style terminal theme generation.

## Run

```sh
swift run mwall
```

The app runs as a menu bar utility and hides its Dock icon.

When "all desktops" is enabled, MWall uses System Events to update every macOS desktop/Space. macOS may ask you to allow MWall to control System Events the first time this runs.

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
- Apply to the current desktop or all macOS desktops/Spaces.
- Favorites and recent wallpaper history.
- Dark and light palette extraction from the applied wallpaper.
- Terminal theme output for Kitty, Alacritty, WezTerm, Ghostty, iTerm2, and Terminal.app helper script.
- Best-effort terminal reload hooks for Kitty, WezTerm, iTerm2 import, and Terminal.app.
- Launch at Login toggle when running as `MWall.app`.

## Unsplash

MWall uses the official Unsplash JSON API. Add your Unsplash Access Key in the popover, then switch to the Unsplash source or click "换一批" to fill the featured wallpaper pool.

Unsplash API JSON requests are rate-limited by Unsplash, while image file requests from `images.unsplash.com` are not counted as API requests. MWall therefore keeps a local two-layer cache under `~/Library/Caches/MWall/Unsplash`:

- `Previews/`: 600x338 preview images used by the wallpaper grid.
- `Full/`: 3840x2160 images downloaded only when a wallpaper is applied.
- `metadata.json`: cached Unsplash photo metadata and local file paths.

## Generated Theme Files

- Kitty: `~/.config/kitty/themes/mwall.conf`, `mwall-dark.conf`, `mwall-light.conf`
- Alacritty: `~/.config/alacritty/themes/mwall.toml`, `mwall-dark.toml`, `mwall-light.toml`
- WezTerm: `~/.config/wezterm/colors/mwall.toml`, `mwall-dark.toml`, `mwall-light.toml`
- Ghostty: `~/.config/ghostty/themes/mwall`, `mwall-dark`, `mwall-light`
- iTerm2: `~/Library/Application Support/MWall/MWall.itermcolors`, `MWall Dark.itermcolors`, `MWall Light.itermcolors`
- Terminal.app helper: `~/Library/Application Support/MWall/Apply-MWall-Terminal.applescript`, plus dark/light variants

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
