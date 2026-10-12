import AppKit
import SwiftUI

// Explicit property-wrapper alias also works with SDKs whose new State macro plugin is absent.
private typealias ViewState<Value> = SwiftUI.State<Value>

enum MWallPage: String, CaseIterable, Identifiable {
    case wallpapers = "壁纸"
    case palettes = "配色"
    case settings = "设置"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @ViewState private var page: MWallPage
    @ViewState private var darkPreview = true

    init(initialPage: MWallPage = .wallpapers, darkPreview: Bool = true) {
        _page = ViewState(initialValue: initialPage)
        _darkPreview = ViewState(initialValue: darkPreview)
    }

    var body: some View {
        VStack(spacing: 0) {
            navigation
            Divider()
            Group {
                switch page {
                case .wallpapers: library
                case .palettes: paletteEditor
                case .settings: preferences
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            actionBar
        }
        .frame(minWidth: 440, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: store.previewIdentity) { await store.refreshPalettePreview() }
    }

    private var navigation: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("MWall").font(.system(size: 20, weight: .semibold))
                Spacer()
                if store.isWorking {
                    ProgressView().controlSize(.small).accessibilityLabel("正在处理")
                }
                Menu {
                    Button("添加壁纸文件夹", systemImage: "folder.badge.plus") {
                        store.chooseLocalFolder()
                    }
                    Button("重新扫描图库", systemImage: "arrow.clockwise") { store.refreshLibrary() }
                    Divider()
                    Button("退出 MWall", systemImage: "power") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17))
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("更多操作")
            }
            Picker("页面", selection: $page) {
                ForEach(MWallPage.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(16)
        .background(.bar)
    }

    private var library: some View {
        VStack(spacing: 0) {
            HStack {
                Picker(
                    "来源",
                    selection: Binding(
                        get: { store.settings.currentSource }, set: { store.setSource($0) }
                    )
                ) {
                    ForEach(WallpaperKind.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .disabled(store.isWorking)
                .fixedSize()
                Text("\(store.visibleWallpapers.count) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if store.settings.currentSource == .unsplash {
                    Button("换一批", systemImage: "arrow.triangle.2.circlepath") {
                        store.refreshUnsplashBatch()
                    }
                    .disabled(store.isWorking)
                } else if store.settings.currentSource == .wallhaven {
                    Button(
                        store.settings.wallhavenSearch.sorting == .random ? "换一批" : "刷新",
                        systemImage: "arrow.triangle.2.circlepath"
                    ) { store.refreshWallhaven() }
                    .disabled(store.isWorking)
                } else if store.settings.currentSource == .local {
                    Button("添加文件夹", systemImage: "folder.badge.plus") { store.chooseLocalFolder() }
                }
            }
            .padding(16)

            if store.settings.currentSource == .wallhaven {
                wallhavenFilters
            }

            if store.visibleWallpapers.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "photo.on.rectangle")
                } description: {
                    Text(emptyDetail)
                } actions: {
                    if store.settings.currentSource == .local {
                        Button("添加文件夹") { store.chooseLocalFolder() }
                    } else if store.settings.currentSource == .unsplash {
                        Button("设置 Unsplash") { page = .settings }
                    } else if store.settings.currentSource == .wallhaven {
                        Button("加载壁纸") { store.refreshWallhaven() }.disabled(store.isWorking)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 16
                    ) {
                        ForEach(store.visibleWallpapers) { item in
                            WallpaperTile(
                                item: item, selected: store.currentWallpaper?.id == item.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            if store.settings.currentSource == .wallhaven {
                HStack {
                    Text("SFW · 横屏 · 1080p+").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.refreshWallhaven(page: store.wallhavenPage - 1, preserveSeed: true)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("上一页")
                    .disabled(store.wallhavenPage <= 1)
                    Text("\(store.wallhavenPage) / \(store.wallhavenLastPage)")
                        .font(.caption).monospacedDigit()
                    Button {
                        store.refreshWallhaven(page: store.wallhavenPage + 1, preserveSeed: true)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel("下一页")
                    .disabled(store.wallhavenPage >= store.wallhavenLastPage)
                }
                .disabled(store.isWorking || !store.wallhavenResultsMatchSearch)
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
    }

    private var wallhavenFilters: some View {
        VStack(spacing: 10) {
            HStack {
                TextField("搜索关键词或标签", text: $store.settings.wallhavenSearch.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.refreshWallhaven() }
                Button("搜索") { store.refreshWallhaven() }
            }
            HStack(spacing: 16) {
                Picker("分类", selection: $store.settings.wallhavenSearch.category) {
                    ForEach(WallhavenCategory.allCases) { Text($0.title).tag($0) }
                }
                Picker("排序", selection: $store.settings.wallhavenSearch.sorting) {
                    ForEach(WallhavenSorting.allCases) { Text($0.title).tag($0) }
                }
            }
        }
        .disabled(store.isWorking)
        .padding(.horizontal, 16).padding(.bottom, 12)
        .onChange(of: store.settings.wallhavenSearch.category) { _, _ in store.refreshWallhaven() }
        .onChange(of: store.settings.wallhavenSearch.sorting) { _, _ in store.refreshWallhaven() }
    }

    private var paletteEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let item = store.currentWallpaper {
                    HStack(spacing: 12) {
                        WallpaperThumbnail(url: item.url)
                            .frame(width: 92, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("壁纸里的颜色").font(.system(size: 16, weight: .semibold))
                            Text(item.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Button("选壁纸") { page = .wallpapers }.controlSize(.small)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("配色方案", selection: $store.settings.paletteStyle) {
                            ForEach(PaletteStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(store.isWorking)
                        Text(store.settings.paletteStyle.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Text("效果预览").font(.headline)
                        Spacer()
                        Picker("预览外观", selection: $darkPreview) {
                            Text("深色").tag(true)
                            Text("浅色").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 126)
                    }
                    if let pair = store.previewPalettes {
                        ThemePreview(palette: darkPreview ? pair.dark : pair.light)
                    } else if let error = store.previewError {
                        ContentUnavailableView(
                            "无法生成预览", systemImage: "exclamationmark.triangle",
                            description: Text(error)
                        )
                        .frame(minHeight: 220)
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("正在从壁纸取色").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                    }
                    if store.usesThumbnailPreview {
                        Label("当前使用缩略图预览，应用时会从原图生成。", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("同步到应用").font(.headline)
                            Text(targetSummary).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("管理") { page = .settings }.controlSize(.small)
                    }
                } else {
                    ContentUnavailableView(
                        "先选择一张壁纸", systemImage: "paintpalette",
                        description: Text("从壁纸提取颜色，为你的应用生成主题。"))
                    Button("浏览壁纸") { page = .wallpapers }
                }
            }
            .padding(16)
        }
    }

    private var preferences: some View {
        Form {
            Section("日常使用") {
                Toggle("应用到所有桌面", isOn: $store.settings.applyToAllScreens)
                Toggle("换壁纸时同步配色", isOn: $store.settings.applyThemeAfterWallpaperChange)
                Toggle("生成主题后刷新终端", isOn: $store.settings.reloadTerminalsAfterThemeChange)
                Toggle(
                    "登录时启动",
                    isOn: Binding(
                        get: { store.settings.launchAtLogin }, set: { store.setLaunchAtLogin($0) }
                    ))
            }
            Section {
                ForEach(ThemeTarget.allCases) { target in
                    Toggle(
                        target.displayName,
                        isOn: Binding(
                            get: { store.settings.enabledThemeTargets.contains(target) },
                            set: { _ in store.toggleThemeTarget(target) }
                        ))
                }
                Text(
                    "终端和编辑器首次生成后选择 mwall 主题。Pi 支持实时更新；Codex CLI 需要新建会话。Codex App 自动同步浅色与深色配色，重启 App 后生效。"
                )
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("同步到应用")
            }
            Section("Unsplash") {
                HStack {
                    SecureField("Access Key", text: $store.settings.unsplashAccessKey)
                    Button {
                        store.pasteUnsplashAccessKey()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("粘贴 Access Key")
                    .accessibilityLabel("粘贴 Unsplash Access Key")
                }
                Stepper(
                    "缓存上限 \(store.settings.unsplashCacheLimitMB) MB",
                    value: $store.settings.unsplashCacheLimitMB, in: 100...5000, step: 100
                )
                .monospacedDigit()
                HStack {
                    Text("已使用约 \(CacheManager.unsplashCacheSizeMB()) MB")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清理缓存") { store.cleanupCache() }
                }
            }
            Section("Wallhaven") {
                HStack {
                    SecureField(
                        store.hasWallhavenAPIKey ? "输入新 Key 以替换" : "API Key（可选）",
                        text: $store.wallhavenAPIKey)
                    Button {
                        store.pasteWallhavenAPIKey()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("粘贴 Wallhaven API Key")
                    .accessibilityLabel("粘贴 Wallhaven API Key")
                    Button("保存") { store.saveWallhavenAPIKey() }
                        .disabled(
                            store.wallhavenAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty)
                }
                HStack {
                    Text(store.hasWallhavenAPIKey ? "已保存到 macOS 钥匙串" : "未配置密钥，使用匿名访问")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if store.hasWallhavenAPIKey {
                        Button("移除密钥", role: .destructive) { store.removeWallhavenAPIKey() }
                    }
                }
                Text("密钥可在 Wallhaven 账户设置中获取。未填写也可搜索；始终只显示 SFW 壁纸。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Stepper(
                    "缓存上限 \(store.settings.wallhavenCacheLimitMB) MB",
                    value: $store.settings.wallhavenCacheLimitMB, in: 100...5000, step: 100
                )
                .monospacedDigit()
                HStack {
                    Text("已使用约 \(CacheManager.cacheSizeMB(in: StorePaths.wallhaven)) MB")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清理缓存") { store.cleanupWallhavenCache() }
                }
            }
            Section("本地文件夹") {
                ForEach(store.localFolders) { folder in
                    HStack {
                        Label(folder.url.lastPathComponent, systemImage: "folder")
                            .help(folder.url.path)
                        Spacer()
                        Button("移除") { store.removeLocalFolder(folder.url) }.controlSize(.small)
                    }
                }
                Button("添加文件夹", systemImage: "folder.badge.plus") { store.chooseLocalFolder() }
            }
        }
        .formStyle(.grouped)
        .disabled(store.isWorking)
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.lastMessage.isEmpty {
                Text(store.lastMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("状态：\(store.lastMessage)")
            }
            HStack(spacing: 10) {
                if page == .wallpapers {
                    Button("随机", systemImage: "shuffle") { store.applyRandomWallpaper() }
                    Spacer()
                    Button {
                        page = .palettes
                    } label: {
                        Label(store.settings.paletteStyle.title, systemImage: "paintpalette")
                    }
                    .help("查看配色方案")
                    Button("设为壁纸") {
                        if let item = store.currentWallpaper { store.applyWallpaper(item) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.currentWallpaper == nil)
                } else if page == .palettes {
                    Button("复制 Codex App", systemImage: "doc.on.doc") {
                        store.copyCodexThemeForSelectedOrLatest()
                    }
                    .disabled(store.currentWallpaper == nil)
                    Spacer()
                    Button("生成并应用", systemImage: "paintpalette.fill") {
                        store.applyThemeForSelectedOrLatest()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        store.currentWallpaper == nil || store.settings.enabledThemeTargets.isEmpty)
                } else {
                    Text("偏好自动保存").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("完成") { page = .wallpapers }
                }
            }
            .controlSize(.large)
            .disabled(store.isWorking)
        }
        .padding(16)
        .background(.bar)
    }

    private var targetSummary: String {
        let names = ThemeTarget.allCases.filter { store.settings.enabledThemeTargets.contains($0) }
            .map(
                \.displayName)
        return names.isEmpty ? "尚未选择应用" : names.joined(separator: " · ")
    }
    private var emptyTitle: String {
        switch store.settings.currentSource {
        case .favorite: "收藏你喜欢的壁纸"
        case .history: "还没有使用记录"
        case .local: "把你的壁纸放进来"
        default: "还没有可用壁纸"
        }
    }
    private var emptyDetail: String {
        switch store.settings.currentSource {
        case .favorite: "点击图片上的爱心，方便下次找到。"
        case .history: "应用过的壁纸会出现在这里。"
        case .local: "添加本地文件夹，即可浏览其中的图片。"
        case .unsplash: "在设置中填入 Access Key，再点“换一批”。"
        case .wallhaven: "默认浏览二次元横屏壁纸，也可以搜索关键词或切换分类。API Key 为可选项。"
        default: "重新扫描图库后再试。"
        }
    }
}

private struct WallpaperTile: View {
    @EnvironmentObject private var store: AppStore
    let item: WallpaperItem
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Button {
                    store.selectWallpaper(item)
                } label: {
                    WallpaperThumbnail(url: item.url)
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                        )
                        .overlay(alignment: .bottomLeading) {
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.accentColor)
                                    .font(.system(size: 18))
                                    .padding(8)
                            }
                        }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("选择壁纸：\(item.title)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                Button {
                    store.toggleFavorite(item)
                } label: {
                    Image(systemName: store.isFavorite(item) ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(store.isFavorite(item) ? Color.red : .primary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .padding(5)
                .accessibilityLabel(store.isFavorite(item) ? "取消收藏" : "收藏壁纸")
            }
            Text(
                item.id.hasPrefix("unsplash:")
                    ? (item.source?.replacingOccurrences(of: "Photo by ", with: "") ?? item.title)
                    : item.title
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .help(item.title)
    }
}

struct WallpaperThumbnail: View {
    let url: URL
    var body: some View {
        if let image = NSImage(contentsOf: url) {
            GeometryReader { geometry in
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
        } else {
            Rectangle().fill(.quaternary)
                .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
    }
}
