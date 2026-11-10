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
`Index.plist` 中 `Desktop.Content.Choices[0].Files` 保持为空，不手工填入旧资料中的 `[{ relative = file:///... }]`。此前该写法曾导致桌面路径更新但画面不换。设置页预览不能只靠修改索引恢复：所有桌面的应用顺序必须是写索引、重载墙纸代理，最后调用 `NSWorkspace.setDesktopImageURL` 注册当前屏幕。macOS 27.0（26A428）上已复现旧顺序导致重开设置后显示黑底问号，并验证新顺序在重开设置后保留正确预览。
_Avoid_: 自造 Files = [{ relative = ... }]

**已应用壁纸副本**:
应用桌面时拷贝到 `~/Library/Application Support/MWall/Applied/current-<uuid>.<ext>`。必须每次换新文件名：若反复覆盖同一个 `current.jpg`，`NSWorkspace` / WallpaperAgent 会认为 URL 未变而不刷新桌面。桌面引用应指向这份副本，而不是 Unsplash 的 Caches 原图。
_Avoid_: 固定 current.jpg 原地覆盖, 直接把 Caches/Unsplash/Full 路径写入 Index.plist

**收藏缩略图**:
收藏图片的预览是持久数据，保存在 `~/Library/Application Support/MWall/Favorites`，不参与图源缓存淘汰。`thumbnailURL` 只供展示，`url` 和原图字段保留原用途。旧收藏在启动或进入收藏页时迁移：优先读取本地缩略图或原图，缺失时从原图源恢复预览；网络失败保留收藏条目，下次进入收藏可重试。
_Avoid_: 把收藏缓存路径当作持久副本, 用缩略图覆盖原图路径

**Wallhaven 筛选**:
筛选条件与 wallhaven.cc 网页搜索栏一一对应，全部显式写入 API 请求，避免带 API Key 时被账户默认设置覆盖。返回结果仍在本地复核内容分级、分类、分辨率和横竖方向。NSFW 只有在钥匙串中存有 API Key 时才会发送；没有密钥或未选任何分级时回退为 SFW，未选分类等同全部分类。筛选面板的修改在收起面板时合并为一次搜索。网页端的 AI 图片开关在公开 API 中无效，因此不提供。
_Avoid_: 每切换一个选项就请求一次, 依赖账户默认 purity
