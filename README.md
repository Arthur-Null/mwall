# MWall

MWall 是原生 macOS 菜单栏壁纸应用。它能从壁纸中提取配色，提供四种生成风格，并将深浅色主题同步到终端、编辑器和编程助手。

## 运行

开发环境需要 macOS 14 或更高版本、Swift 6 工具链和 Go 1.25 或更高版本。Go 仅用于构建内置的 Aether 配色引擎。

```sh
tools/build_aether.sh
swift run mwall
```

应用启动后显示在菜单栏，不显示 Dock 图标。

启用“所有桌面”时，MWall 会更新 macOS 壁纸存储，让不可见的 Spaces 也使用同一张图片，再通过 `NSWorkspace` 刷新可见显示器。较旧的 macOS 可能回退到 System Events，并请求自动化权限。

应用壁纸前，MWall 会将图片复制到 `~/Library/Application Support/MWall/Applied/` 下的独立文件，再写入系统壁纸索引。每次使用新路径，既能触发桌面刷新，也能避免清理 Unsplash 缓存时影响正在使用的壁纸。索引中的 `Files` 保持为空；旧资料中提到的 `[{ relative = ... }]` 结构会导致当前 macOS 的 WallpaperAgent 无法加载图片。

## 构建应用包

```sh
tools/package_app.sh
open dist/MWall.app
```

脚本生成 `dist/MWall.app`，通过 `LSUIElement` 将它设为菜单栏应用，并执行临时签名。默认应用包不启用沙箱，因为 MWall 需要向 `~/.config` 写入终端主题。

仅在测试沙箱兼容性时使用：

```sh
MWALL_SANDBOX=1 tools/package_app.sh
```

### 下载与安装

在 [GitHub Releases](https://github.com/Arthur-Null/mwall/releases) 下载与机型对应的 ZIP：

- Apple Silicon：`MWall-v版本号-macos-arm64.zip`。
- Intel：`MWall-v版本号-macos-x86_64.zip`。

解压后将 `MWall.app` 拖入“应用程序”。发布包内置 Aether，无需另外安装 Go 或 Swift。每个 ZIP 都附有 `.sha256` 文件，在同一目录执行以下命令即可校验：

```sh
shasum -a 256 -c MWall-v0.2.0-macos-arm64.zip.sha256
```

应用要求 macOS 14 或更高版本，目前采用临时签名，尚未使用 Apple Developer ID 签名或通过公证。首次打开可能被系统拦截；确认来源和校验值后，可在“系统设置 → 隐私与安全性”中允许打开，无需关闭系统安全保护。私有仓库的发布附件仅对有仓库访问权限的用户开放。

## 功能

- 在菜单栏面板中浏览壁纸。
- 首次启动时生成内置备用壁纸。
- 添加本地壁纸文件夹。
- 使用安全作用域书签保存用户选择的文件夹，为沙箱构建保留支持。
- Unsplash 精选壁纸池，使用预览图和原图两级缓存。
- Wallhaven 关键词搜索、分类、排序和分页，默认显示全年龄二次元壁纸。
- 将壁纸应用到当前桌面或所有 macOS 桌面与 Spaces。
- 收藏和最近使用的壁纸记录。
- 从壁纸中提取深色与浅色配色。
- 导出 Kitty、Alacritty、WezTerm、Ghostty、iTerm2 主题及 Terminal.app 辅助脚本。
- 尽可能自动重载 Kitty、WezTerm、iTerm2 导入及 Terminal.app 主题。
- 生成 Neovim 配色，实时更新已打开的编辑器，兼容 AstroNvim 和 LazyVim。
- 生成支持原生实时更新的 Pi 主题，以及 Codex CLI 语法高亮主题。
- 按需启用 Codex App 深浅色配色同步，重启目标应用后生效。
- 以 `MWall.app` 运行时支持登录启动。

## 配色风格与界面

菜单栏面板分为三个页面：**壁纸**用于浏览图片，**配色**用于选择生成风格和预览代码，**设置**用于管理目标应用、自动化、文件夹及在线壁纸源。

- **Aether**：使用上游提交 `f0ae849966cc038a21808170b21e07772cb3619c` 的普通模式生成器，MWall 不重新调整其配色。上游无法解码 HEIC 和 TIFF，因此这两种格式先由 macOS 转为临时 sRGB PNG；限制范围内的 JPEG、PNG、GIF 和 WebP 直接传入。原生格式图片，以及超过上游单边 16,384 像素或总计 4,000 万像素限制的图片，会等比缩放至最长边不超过 4,096 像素后导入。
- **忠实壁纸**：默认风格，保留壁纸色相，浅色背景带少量壁纸色调，OKLab 色度约不超过 0.012。
- **柔和**：参考 Noctalia 的柔和风格，使用接近中性的浅色背景，色度约不超过 0.008，并降低强调色的饱和感。
- **鲜艳**：提高强调色的色度，同时保持浅色背景克制。

旧版单一种子色、固定色相的生成器已移除。已有设置会迁移到“忠实壁纸”，保留目标应用及其他偏好。切换风格只更新预览，不写入主题文件；“生成并应用”、复制 Codex App 配色，以及更换壁纸后自动生成主题，均使用保存的风格。

每种风格同时生成浅色和深色配色。在线壁纸优先用已缓存的原图预览；原图尚未下载时，界面会标明使用缩略图。应用壁纸时会先下载或复用原图，再提取颜色。生成过程不阻塞界面线程，缓存按图片路径、修改时间、大小和风格区分。

MWall 自有的三种风格使用保持宽高比的 sRGB 采样和 OKLab 聚类，以真实像素作为代表色。目标是主文字与背景对比度达到 7:1、ANSI 强调色达到 4.5:1，但这不保证所有语法角色都能明显区分。壁纸缺少某些色相时，传统 ANSI 红色、绿色的语义也可能减弱。Aether 保留自身的对比度和色相处理方式。

### Aether 构建依赖

`tools/build_aether.sh` 将固定版本的上游源码拉取到 `.build/aether-source`，构建一个调用上游原有 CLI 逻辑的小型启动器。仅构建辅助程序时需要 Go，首次构建可能自动下载所需的 Go 工具链。打包后的 `MWall.app` 已包含可执行文件，运行时不需要单独安装 Aether 或 Go。

MWall 不调用 Aether 的主题应用命令。提取配色时可使用 Aether 的标准缓存 `~/.cache/aether/color-cache`。开发和测试时可通过 `MWALL_AETHER_BIN` 指定辅助程序路径；固定源码版本记录在 `tools/aether/UPSTREAM_REVISION`。

### 界面验证

使用隔离的测试状态渲染真实 SwiftUI 界面，不修改设置、壁纸或主题：

```sh
"$(swift build --show-bin-path)/mwall" --snapshot-ui /tmp/mwall-palette.png \
  "$HOME/Library/Caches/MWall/Unsplash" 540 740 配色 light faithful
```

页面可选“壁纸”“配色”或“设置”，外观可选 `light` 或 `dark`。内容区域最小支持 440 × 620 点。测试输入使用缓存中的 `metadata.json` 和 `Full/` 原图，生成的截图用于界面验证，不是设计示意图。

验证实际配色输出是否与已审阅的对比 JSON 一致：

```sh
MWALL_PALETTE_REFERENCE=/path/to/palette-preview/index.json \
MWALL_PALETTE_CACHE="$HOME/Library/Caches/MWall/Unsplash" swift test -c release
```

## Unsplash

MWall 使用官方 Unsplash JSON API。在面板中填入 Unsplash Access Key 后，切换到 Unsplash 壁纸源或点击“换一批”，即可填充精选壁纸池。

Unsplash 的 JSON API 请求受其速率限制，来自 `images.unsplash.com` 的图片请求不计入 API 请求次数。MWall 在 `~/Library/Caches/MWall/Unsplash` 下维护两级本地缓存：

- `Previews/`：壁纸网格使用的 600 × 338 预览图。
- `Full/`：应用壁纸时才下载的 3840 × 2160 图片。
- `metadata.json`：Unsplash 图片元数据和本地路径。

## Wallhaven

在壁纸源选择器中选择 **Wallhaven**，默认显示至少 1920 × 1080 的全年龄横向二次元壁纸。支持按关键词或标签搜索，在二次元、综合、人物、全部分类之间切换，以及随机、最新、月度热门、收藏最多、浏览最多排序。收藏数和浏览量从高到低排列；浏览量不是下载量，与 Noctalia 插件使用的排序参数一致。分页保留随机种子，点击“换一批”会开始新的随机序列。

API 密钥可选。在“设置 → Wallhaven”粘贴账户设置中的密钥并点击“保存”，MWall 会将其保存在 macOS 钥匙串中，仅通过 API 请求的 `X-API-Key` 请求头发送，不写入设置 JSON、搜索 URL、图片请求或缓存元数据。点击“移除密钥”恢复匿名访问。两种模式都显式请求全年龄内容，不继承账户的内容分级偏好。

Wallhaven 官方 API 文档标明每分钟 45 次请求，但未说明认证后有更高额度，因此 MWall 不承诺配置密钥能提高限额。密钥无效和请求限流会显示不同提示；新搜索失败时保留此前的缓存结果。

Wallhaven 使用独立缓存 `~/Library/Caches/MWall/Wallhaven`：`Previews/` 存放缩略图，`Full/` 按原始格式保存原图，`metadata.json` 记录最近一次成功搜索的页面，不包含凭据。应用壁纸或生成主题时按需下载原图。收藏和历史记录保留原始壁纸来源，切换壁纸源后也能正确加载；各来源拥有独立的缓存上限。

实现参考 [Noctalia Wallhaven 插件](https://github.com/noctalia-dev/official-plugins/tree/main/wallhaven)和 [Wallhaven 官方 API](https://wallhaven.cc/help/api)，采用原生 Swift 与 SwiftUI，不引入插件运行时。

可手动启用匿名网络测试：

```sh
MWALL_WALLHAVEN_LIVE=/tmp/mwall-wallhaven-live swift test --filter wallhavenLiveSmoke
```

测试将一页全年龄预览图和一张原图下载到指定目录，不应用壁纸或修改设置。该目录也可作为 Wallhaven 默认搜索的 `--snapshot-ui` 输入。

## Codex App 配色同步

在“设置 → 同步到应用”中启用 **Codex App**，然后生成主题，或在启用自动生成主题的情况下更换壁纸。此目标默认关闭，包括全新安装。开启后，MWall 将壁纸生成的深浅色桌面配色自动写入用户的 Codex 配置，无需再复制和导入主题字符串。

配色在桌面应用下次启动时生效。运行中的应用会将主题保留在内存中，因此 MWall 显示“重启 App 后生效”，不会自行重启目标应用。“复制 Codex App”按钮仍保留，可用于手动导入到正在运行的应用或旧版本。

同步需要较新的 Codex App 或 Codex CLI，并支持 `config.toml` 中的 `desktop` 设置。已验证 Codex CLI 0.154.0。MWall 会在 ChatGPT.app、Codex.app 内置目录、Homebrew、常见用户二进制目录和进程 `PATH` 中查找 CLI；配置目录优先使用 `CODEX_HOME`，否则使用 `~/.codex/config.toml`。

MWall 通过官方 app-server 的 `config/read` 和 `config/batchWrite` API 保留 TOML 结构，原子更新深浅色配色，并利用版本检查拒绝并发冲突。同步修改强调色、背景、前景以及差异和技能相关语义色，保留字体、对比度、透明度、外观模式、代码主题及其他配置。缺失字段会补充有效默认值，相同配色不会重复写入。

CLI 缺失、版本不兼容、配置无效、冲突和超时都会给出提示，不影响其他已选目标的主题导出。同步在界面线程之外执行，不发起模型请求。接口参考：[Codex app-server 配置 API](https://developers.openai.com/codex/app-server/)。

针对已安装 CLI 运行隔离集成测试：

```sh
MWALL_CODEX_CLI=/opt/homebrew/bin/codex swift test
```

测试使用临时配置，检查无关偏好保留、重复更新和版本冲突，不修改用户的 Codex 配置。

## 生成的主题文件

- Kitty：`~/.config/kitty/themes/mwall.conf`、`mwall-dark.conf`、`mwall-light.conf`
- Alacritty：`~/.config/alacritty/themes/mwall.toml`、`mwall-dark.toml`、`mwall-light.toml`
- WezTerm：`~/.config/wezterm/colors/mwall.toml`、`mwall-dark.toml`、`mwall-light.toml`
- Ghostty：`~/.config/ghostty/themes/mwall`、`mwall-dark`、`mwall-light`
- iTerm2：`~/Library/Application Support/MWall/MWall.itermcolors`、`MWall Dark.itermcolors`、`MWall Light.itermcolors`
- Terminal.app 辅助脚本：`~/Library/Application Support/MWall/Apply-MWall-Terminal.applescript` 及深浅色版本
- Neovim：`~/.config/nvim/colors/mwall.lua`、`mwall-dark.lua`、`mwall-light.lua`
- Neovim 实时重载插件：`~/.config/nvim/plugin/mwall-reload.lua`
- Pi：`~/.pi/agent/themes/mwall.json`、`mwall-dark.json`、`mwall-light.json`
- Codex CLI：`~/.codex/themes/mwall.tmTheme`、`mwall-dark.tmTheme`、`mwall-light.tmTheme`

多数终端需要在主配置中引用主题文件，或在应用界面中手动导入。

## 终端主题导入

Kitty：

```conf
include themes/mwall.conf
```

Alacritty：

```toml
import = ["~/.config/alacritty/themes/mwall.toml"]
```

WezTerm：

```lua
config.color_scheme_dirs = { os.getenv("HOME") .. "/.config/wezterm/colors" }
config.color_scheme = "mwall"
```

Ghostty：

```conf
theme = dark:mwall-dark,light:mwall-light
```

对于不自动切换深浅色主题的终端，MWall 写入主题时会根据当时的 macOS 外观重新生成 `mwall.conf`、`mwall.toml` 或 `mwall`。

## Neovim 实时主题

在 MWall 中启用 Neovim 目标并生成主题，然后在编辑器配置中选择 `mwall`：

```lua
-- 原生 Neovim
vim.cmd.colorscheme("mwall")
```

AstroNvim 用户可在 `AstroNvim/astroui` 选项中设置 `colorscheme = "mwall"`；LazyVim 用户可在 `LazyVim/LazyVim` 选项中设置。MWall 只写入自己的配色和运行时插件文件，不修改插件声明或 `init.lua`。

运行时插件每秒检查当前使用的 MWall 配色文件。文件更新后，每个已打开的 Neovim 都会自动重新加载并重绘，无需切换焦点，支持文件的原子替换。`ColorScheme` 回调正常执行，插件界面及用户的高亮、透明度覆盖设置会重新应用。内容不变时不触发重载，切换到其他配色后暂停 MWall 更新。

### 在已打开的编辑器中首次启用

对于安装重载插件前就已打开的编辑器，生成主题后执行一次：

```vim
:runtime plugin/mwall-reload.lua
```

这样无需重启 Neovim 即可启用实时更新。新会话及后续选择 MWall 配色时会自动加载插件，之后更新壁纸或主题不再需要手动执行命令。

### 深浅色版本

`mwall` 反映生成主题时的 macOS 外观。仅切换系统外观不会自动触发 MWall 重新生成文件。如果需要独立跟随外观变化，可保留已有的 `auto-dark-mode.nvim` 集成：

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

实时更新保留当前使用的版本，不依赖终端重载设置。设置 `vim.g.mwall_auto_reload = false` 可关闭 Neovim 实时更新。

### 验证

安装 Neovim 后运行 `swift test`，也可通过 `NVIM_BIN` 指定可执行文件。集成测试使用隔离的临时配置和同一个 Neovim 进程，验证三种配色、原子替换、内容不变时的行为、高亮覆盖、未保存缓冲区、无效文件恢复及禁用行为，不修改用户的编辑器配置。

## Pi 与 Codex CLI

在 MWall 中启用 **Pi** 或 **Codex CLI**，再点击“生成主题”，或在启用自动生成主题时应用壁纸。已有目标选择会保留，因此旧安装需要手动启用新目标；全新设置默认包含这两个目标。

两种导出器均生成 `mwall`、`mwall-dark` 和 `mwall-light`，其中 `mwall` 使用生成时的 macOS 外观。内容不变时不重写文件。导出器不修改目标应用设置，也不会自动选择主题；独立的 Codex App 目标则按前文说明更新桌面配色设置。

### Pi

在 Pi 的 `/settings` 中选择一次 `mwall`。之后 Pi 的原生文件监听器会自动载入更新后的主题，包括原子替换，无需重启或手动重载。界面强调色、消息和工具面板、Markdown、语法高亮及差异颜色共用壁纸配色；终端底色仍来自终端本身，建议同时启用对应终端的主题输出。

若要跟随终端的深浅色外观，可在 Pi 设置中选择主题对，或运行：

```sh
pi --use-theme mwall-light/mwall-dark
```

Pi 检测的是终端外观，并非 macOS 主题调度器。每次 MWall 生成主题时都会刷新深浅色两个版本。

### Codex CLI

在 Codex CLI 中运行 `/theme`，选择 `mwall`、`mwall-dark` 或 `mwall-light`，选择结果保存为 `tui.theme`。这些 TextMate 主题用于代码块和差异的语法高亮，与桌面应用的“复制 Codex App”导入字符串相互独立，不覆盖所有终端界面元素。

已验证 Codex CLI 0.154.0 可以加载并预览这些主题，但它会缓存已加载的主题：外部替换文件后，重新打开 `/theme` 仍可能显示旧配色。新建 Codex CLI 会话才能可靠载入更新后的颜色。`/theme` 可以不重启就切换已有版本，但此导出器不提供文件自动重载或 Pi 式的深浅色主题配对。

### 自定义路径与验证

如果 MWall 进程中存在 `PI_CODING_AGENT_DIR` 或 `CODEX_HOME` 环境变量，导出器会使用对应目录。通过 Finder 启动的应用通常不会继承只在 shell 中设置的变量，否则使用前文列出的默认路径。

`swift test` 检查序列化、配色映射、已保存设置、目录覆盖及内容不变时的处理。要额外测试已安装 Pi 的主题加载器和文件监听器，可将 `PI_PACKAGE_DIR` 指向 `@earendil-works/pi-coding-agent` 包的根目录：

```sh
PI_PACKAGE_DIR="$(npm root -g)/@earendil-works/pi-coding-agent" swift test
```

Pi 集成测试使用临时主题，不影响用户正在运行的会话，覆盖三种配色、重复原子替换、无效文件恢复及深浅色主题对解析。接口参考：[Pi 主题](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/themes.md)和 [Codex CLI 自定义](https://developers.openai.com/zh-Hans/docs/cli-customization)。

## CI 与发布

GitHub Actions 在向 `main` 推送、提交 PR 或手动触发 **CI** 时，在 Apple Silicon 和 Intel 的 macOS 15 runner 上执行以下步骤：

1. 安装 Go 和 Neovim，构建固定版本的 Aether。
2. 运行 `swift test -c release`，包括 Neovim 实时重载测试。
3. 打包应用，检查临时签名和两个可执行文件的架构，生成 ZIP 与 SHA-256 校验文件。
4. 将两种架构的产物上传到该次 Actions 运行，保留 14 天。

需要额外环境的 Wallhaven 网络与钥匙串测试、Codex CLI 集成、Pi 实时重载及配色参考对比默认不启用，仍可按前文命令单独运行。工作流默认仅有读取仓库的权限，只有 Release 发布任务具有写入权限；第三方 Action 固定到明确的提交。

本地生成与 CI 相同的当前架构压缩包：

```sh
tools/archive_app.sh
```

### 发布新版本

在主开发机完成以下操作：

1. 更新 `Resources/Info.plist` 中的 `CFBundleShortVersionString` 和递增的 `CFBundleVersion`。
2. 添加 `docs/releases/v版本号.md`，提交并推送，确认 CI 通过。
3. 创建与应用版本一致的标签并推送，例如：

```sh
git tag -a v0.2.0 -m "MWall v0.2.0"
git push origin v0.2.0
```

**Release** 工作流只接受 `v主版本.次版本.修订号` 格式的标签，检查标签与应用版本一致、发布说明存在，再重新运行两种架构的测试和打包。全部成功后才创建 GitHub Release，附上两个 ZIP 和对应校验文件。任一步骤失败都不会发布未经完整验证的应用包。

如果需要重试，优先在失败的运行中选择重新运行失败任务；也可针对已存在的版本标签手动触发 Release 工作流。它不会覆盖已有的同名 Release，不会自动创建标签，也不负责 Apple Developer ID 签名或公证。
