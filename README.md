# MWall

MWall is a native macOS menu bar wallpaper app with Noctalia-style terminal theme generation.

## Run

```sh
swift run mwall
```

The app runs as a menu bar utility and hides its Dock icon.

When "all desktops" is enabled, MWall updates the macOS wallpaper store so hidden Spaces pick up the same image, then refreshes visible displays through `NSWorkspace`. Older macOS versions may fall back to System Events and ask for automation permission.

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
- Neovim colorschemes with live updates for open editors, including AstroNvim and LazyVim.
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
- Neovim: `~/.config/nvim/colors/mwall.lua`, `mwall-dark.lua`, `mwall-light.lua`
- Neovim live reload: `~/.config/nvim/plugin/mwall-reload.lua`

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
