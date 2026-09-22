# MWall

MWall is a macOS wallpaper utility that turns wallpaper choices into desktop appearance and terminal color themes.

## Language

**Unsplash 精选源**:
不依赖用户搜索词的远程壁纸源，从 Unsplash 官方壁纸类内容中拉取横向图片，并组成可浏览壁纸池。
_Avoid_: Unsplash 搜索, 关键词图源

**壁纸池**:
图源当前提供给用户浏览和选择的一组候选壁纸。壁纸池可以由本地缓存和远程拉取结果共同组成。
_Avoid_: 搜索结果, 下载列表

**换一批**:
为远程图源刷新壁纸池的操作。对 Unsplash 精选源而言，它表示从官方壁纸内容中随机选择一页流行横向图片，而不是继续关键词搜索或顺序翻页。
_Avoid_: 下一页, 搜索

**双层缓存**:
远程壁纸的本地缓存分为可快速浏览的预览图和用于真正设置桌面的完整壁纸。预览图用于壁纸池展示，完整壁纸只在用户应用该壁纸时下载或复用。
_Avoid_: 全量预下载, 只缓存原图

**Unsplash API 预算**:
Unsplash 的 API 预算针对 `api.unsplash.com` JSON 请求，而不是 `images.unsplash.com` 图片文件请求。MWall 应减少 metadata 请求次数：优先使用已有壁纸池，不足时一次拉取一批；图片文件缓存用于速度、带宽和磁盘控制，不作为 API 请求预算的主要手段。
_Avoid_: 每张图一次 API 请求, 通过缩略图规避 rate limit

**Unsplash 预览图**:
双层缓存中的浏览用图片，尺寸为 600x338，质量参数 q=75。预览图进入壁纸池后即可用于列表展示，但不代表用户已经下载或应用了该图片。
_Avoid_: 原图预下载, 低清桌面图

**Unsplash 完整壁纸**:
双层缓存中真正用于设置桌面和生成主题的图片，尺寸为 3840x2160，质量参数 q=90。只有用户应用某张 Unsplash 壁纸时才下载，并在此时调用 Unsplash 的 download tracking URL。
_Avoid_: 预览图应用到桌面, 浏览时触发下载统计

**所有桌面**:
把同一张壁纸应用到当前显示器和 Mission Control 中的隐藏 Space。现代 macOS 的持久状态在 `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`，不能只依赖 `System Events desktops`，后者只适合作为旧系统 fallback。
_Avoid_: 当前桌面, 当前显示器, 只刷新 NSWorkspace screen

**壁纸 Configuration**:
`Index.plist` 中 `Desktop.Content.Choices[0].Configuration` 是二进制 plist。当前 macOS 认可的图片结构是 `type = imageFile` 和 `url.relative = file:///...`；不要写旧的扁平 `relative` 字段。
_Avoid_: relative = file:///..., 自造配置结构

**壁纸 Files**:
`Index.plist` 中 `Desktop.Content.Choices[0].Files` 是系统设置墙纸页预览依赖的文件引用数组。图片墙纸应写成 `[{ relative = file:///... }]`，并与 Configuration 指向同一路径。写成空数组时，桌面仍可能靠 Configuration 显示，但设置页会显示黑底缺失占位。
_Avoid_: Files = [], 只写 Configuration

**已应用壁纸副本**:
应用桌面时拷贝到 `~/Library/Application Support/MWall/Applied/current.<ext>` 的稳定副本。系统设置与桌面引用都应指向这里，而不是 Unsplash 的 Caches 原图，避免缓存清理后预览再次缺失。
_Avoid_: 直接把 Caches/Unsplash/Full 路径写入 Index.plist
