import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    private let columns = [
        GridItem(.adaptive(minimum: 118), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            sourceBar
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(store.visibleWallpapers) { item in
                        WallpaperCard(item: item)
                    }
                }
                .padding(12)
            }
            Divider()
            controls
        }
        .frame(minWidth: 430, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MWall")
                    .font(.system(size: 18, weight: .semibold))
                Text(store.lastMessage.isEmpty ? "菜单栏壁纸与终端主题" : store.lastMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                store.refreshLibrary()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("重新扫描")
            Button {
                store.chooseLocalFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("添加本地壁纸文件夹")
        }
        .padding(12)
    }

    private var sourceBar: some View {
        HStack(spacing: 8) {
            ForEach(WallpaperKind.allCases) { source in
                Button {
                    store.setSource(source)
                } label: {
                    Text(source.title)
                        .font(.system(size: 12, weight: store.settings.currentSource == source ? .semibold : .regular))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(sourceBackground(source))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                store.applyRandomWallpaper()
            } label: {
                Label("随机", systemImage: "shuffle")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sourceBackground(_ source: WallpaperKind) -> Color {
        store.settings.currentSource == source ? Color.accentColor.opacity(0.16) : Color.clear
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Toggle("所有桌面", isOn: Binding(
                    get: { store.settings.applyToAllScreens },
                    set: { store.settings.applyToAllScreens = $0 }
                ))
                Toggle("开机启动", isOn: Binding(
                    get: { store.settings.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                Toggle("换壁纸后生成主题", isOn: Binding(
                    get: { store.settings.applyThemeAfterWallpaperChange },
                    set: { store.settings.applyThemeAfterWallpaperChange = $0 }
                ))
                Toggle("刷新终端", isOn: Binding(
                    get: { store.settings.reloadTerminalsAfterThemeChange },
                    set: { store.settings.reloadTerminalsAfterThemeChange = $0 }
                ))
                Spacer()
                Button {
                    store.applyThemeForSelectedOrLatest()
                } label: {
                    Label("生成主题", systemImage: "paintpalette")
                }
            }

            HStack(spacing: 8) {
                ForEach(ThemeTarget.allCases) { target in
                    Toggle(target.displayName, isOn: Binding(
                        get: { store.settings.enabledThemeTargets.contains(target) },
                        set: { _ in store.toggleThemeTarget(target) }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                }
                Spacer()
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Unsplash Access Key", text: Binding(
                            get: { store.settings.unsplashAccessKey },
                            set: { store.settings.unsplashAccessKey = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Button {
                            store.pasteUnsplashAccessKey()
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .help("从剪贴板粘贴 Access Key")
                        TextField("关键词", text: Binding(
                            get: { store.settings.unsplashQuery },
                            set: { store.settings.unsplashQuery = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                        Button {
                            store.fetchUnsplashWallpaper()
                        } label: {
                            Label(store.isWorking ? "获取中" : "获取并应用", systemImage: "cloud.down")
                        }
                        .disabled(store.isWorking)
                    }
                    HStack {
                        Stepper("缓存上限 \(store.settings.unsplashCacheLimitMB) MB", value: Binding(
                            get: { store.settings.unsplashCacheLimitMB },
                            set: { store.settings.unsplashCacheLimitMB = $0 }
                        ), in: 100...5000, step: 100)
                        Text("当前约 \(CacheManager.unsplashCacheSizeMB()) MB")
                            .foregroundStyle(.secondary)
                        Button("清理缓存") {
                            store.cleanupCache()
                        }
                    }
                    .font(.caption)
                }
                .padding(.top, 6)
            } label: {
                Label("Unsplash 与缓存", systemImage: "cloud")
            }

            if !store.localFolders.isEmpty {
                Menu {
                    ForEach(store.localFolders, id: \.id) { folder in
                        Button("移除 \(folder.url.lastPathComponent)") {
                            store.removeLocalFolder(folder.url)
                        }
                    }
                } label: {
                    Label("\(store.localFolders.count) 个本地文件夹", systemImage: "folder")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
    }
}

private struct WallpaperCard: View {
    @EnvironmentObject private var store: AppStore
    let item: WallpaperItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(url: item.url)
                    .frame(height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(store.selectedWallpaperID == item.id ? Color.accentColor : Color.black.opacity(0.12), lineWidth: store.selectedWallpaperID == item.id ? 2 : 1)
                    )

                Button {
                    store.toggleFavorite(item)
                } label: {
                    Image(systemName: store.isFavorite(item) ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(store.isFavorite(item) ? .red : .white)
                        .shadow(radius: 2)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            Text(item.title)
                .font(.caption)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(item.source ?? item.kind.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("应用") {
                    store.applyWallpaper(item)
                }
                .controlSize(.small)
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ThumbnailView: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            ZStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.16))
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
