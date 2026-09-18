// PROTOTYPE preview CLI. Reads cache only; never writes application settings or themes.
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CachedImage: Decodable {
    let id: String
    let url: URL
    let title: String
    let source: String?
    let fullLocalURL: URL?
}
struct Variant: Encodable {
    let id: String
    let palettes: TerminalPalettePair
    var accents: [String: RGBColor]? = nil
    var provenance: AetherProvenance? = nil
}
struct PreviewImage: Encodable {
    let id: String
    let title: String
    let credit: String
    let file: String
    let image: String
    let swatches: [ImageSwatch]
    let variants: [Variant]
}
func jpegDataURL(_ url: URL) throws -> String {
    let source = CGImageSourceCreateWithURL(url as CFURL,nil)!
    let image = CGImageSourceCreateThumbnailAtIndex(source,0,[
        kCGImageSourceCreateThumbnailFromImageAlways:true,
        kCGImageSourceCreateThumbnailWithTransform:true,
        kCGImageSourceThumbnailMaxPixelSize:1440
    ] as CFDictionary)!
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:0.85] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain:"Preview",code:3) }
    return "data:image/jpeg;base64,"+(output as Data).base64EncodedString()
}
let args = CommandLine.arguments
guard args.count == 4 || args.count == 5 else {
    fputs("Usage: palette-preview CACHE_DIRECTORY TEMPLATE_HTML OUTPUT_HTML [AETHER_REFERENCE_JSON]\n",stderr)
    exit(2)
}
let cache = URL(fileURLWithPath:args[1],isDirectory:true)
let template = URL(fileURLWithPath:args[2])
let output = URL(fileURLWithPath:args[3])
let aether = args.count == 5
    ? try JSONDecoder().decode(AetherReference.self, from: Data(contentsOf: URL(fileURLWithPath: args[4])))
    : nil
let cached = try JSONDecoder().decode([CachedImage].self,from:Data(contentsOf:cache.appendingPathComponent("metadata.json")))
let fullFiles = try FileManager.default.contentsOfDirectory(at:cache.appendingPathComponent("Full"),includingPropertiesForKeys:nil)
    .filter { ["jpg","jpeg","png","webp"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
var images: [PreviewImage] = []
var minContrast = Double.infinity
var maxRoundtripError = 0
for rgb in [RGBColor(r:255,g:0,b:0),RGBColor(r:0,g:255,b:0),RGBColor(r:0,g:0,b:255),
            RGBColor(r:0,g:0,b:0),RGBColor(r:255,g:255,b:255),RGBColor(r:57,g:125,b:184)] {
    let result=OKColor(rgb).rgb
    maxRoundtripError=max(maxRoundtripError,max(abs(rgb.r-result.r),abs(rgb.g-result.g),abs(rgb.b-result.b)))
}
for file in fullFiles {
    let id=file.deletingPathExtension().lastPathComponent.replacingOccurrences(of:"unsplash-",with:"")
    let item=cached.first { $0.id == "unsplash:"+id }
    let clusters=try PerceptualPalette.clusters(from:file)
    let total=Double(clusters.reduce(0) { $0+$1.count })
    var variants=[Variant(id:"current",palettes:try PaletteGenerator.generate(from:file))]
    if let aether {
        variants.append(try aether.variant(id: id, file: file))
    }
    for style in PreviewStyle.allCases {
        let pair=PerceptualPalette.pair(clusters,style:style)
        for palette in [pair.dark,pair.light] {
            minContrast=min(minContrast,contrast(palette.foreground,palette.background),
                            contrast(palette.selectionForeground,palette.selectionBackground))
            for c in Array(palette.normal[1...6])+Array(palette.bright[1...6])+[palette.cursor,palette.bright[0]] {
                minContrast=min(minContrast,contrast(c,palette.background))
            }
        }
        variants.append(Variant(id:style.rawValue,palettes:pair))
    }
    images.append(PreviewImage(id:id,title:item?.title ?? id,credit:item?.source ?? "Unsplash",
        file:file.lastPathComponent,image:try jpegDataURL(file),
        swatches:clusters.prefix(12).map { ImageSwatch(hex:$0.color.hex,share:Double($0.count)/total) },
        variants:variants))
    print("Generated \(id): \(variants.count) variants, dark/light, \(clusters.count) image clusters")
}
guard !images.isEmpty else { fatalError("No cached full-resolution images") }
guard minContrast >= 4.5 && maxRoundtripError <= 1 else { fatalError("Palette validation failed") }
let encoder=JSONEncoder()
encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
let data=try encoder.encode(images)
let json=String(decoding:data,as:UTF8.self).replacingOccurrences(of:"<",with:"\\u003c")
let html=try String(contentsOf:template,encoding:.utf8).replacingOccurrences(of:"__PALETTE_DATA__",with:json)
try FileManager.default.createDirectory(at:output.deletingLastPathComponent(),withIntermediateDirectories:true)
try html.write(to:output,atomically:true,encoding:.utf8)
try data.write(to:output.deletingPathExtension().appendingPathExtension("json"),options:.atomic)
print(String(format:"VALIDATION images=%d palettes=%d experimental_min_text_contrast=%.3f roundtrip_error=%d",
             images.count,images.reduce(0) { $0 + $1.variants.count * 2 },minContrast,maxRoundtripError))
if let aether {
    print("AETHER revision=\(aether.commit) mode=\(aether.mode) adjustments=\(aether.adjustments) verified_ansi_slots=\(images.count * 2 * 16)")
}
print("HTML \(output.path)")

