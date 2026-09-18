import SwiftUI

struct ThemePreview: View {
    let palette: TerminalPalette
    private func color(_ rgb: RGBColor) -> Color {
        Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
    private func text(_ value: String, _ rgb: RGBColor) -> Text {
        Text(value).foregroundColor(color(rgb))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("theme.ts")
                    Spacer()
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(color(palette.bright[0]))
                .padding(.horizontal, 16).padding(.vertical, 10)
                Rectangle().fill(color(palette.foreground).opacity(0.12)).frame(height: 1)
                VStack(alignment: .leading, spacing: 6) {
                    text("// 从壁纸到工作空间", palette.bright[0])
                    text("const ", palette.normal[5]) + text("theme = {", palette.foreground)
                    text("  name: ", palette.foreground) + text("\"mwall\"", palette.normal[2])
                        + text(",", palette.foreground)
                    text("  colors: ", palette.foreground) + text("16", palette.normal[3])
                        + text(",", palette.foreground)
                    text("};", palette.foreground)
                    Text(" ")
                    text("function ", palette.normal[5]) + text("apply", palette.normal[4])
                        + text("(theme) {", palette.foreground)
                    text("  return ", palette.normal[5]) + text("render", palette.normal[4])
                        + text("(theme);", palette.foreground)
                    text("}", palette.foreground)
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(color(palette.background))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("代码配色预览，背景 \(palette.background.hex)，字符串 \(palette.normal[2].hex)")
            HStack(spacing: 3) {
                ForEach(Array((palette.normal + palette.bright).enumerated()), id: \.offset) { index, rgb in
                    RoundedRectangle(cornerRadius: 3).fill(color(rgb)).frame(height: 14)
                        .help("ANSI \(index): \(rgb.hex)")
                        .accessibilityLabel("颜色 \(index)，\(rgb.hex)")
                }
            }
            HStack(spacing: 16) {
                Text(String(format: "正文 %.1f:1", MWall.contrast(palette.foreground, palette.background)))
                Text(String(format: "字符串 %.1f:1", MWall.contrast(palette.normal[2], palette.background)))
            }
            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
