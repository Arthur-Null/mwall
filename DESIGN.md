# MWall interface

## Theme
A quiet native macOS wallpaper utility. Photography is the visual anchor. A compact menu bar panel separates browsing, palette preview, and settings. Use native materials and controls rather than simulating glass.

## Palette
Use semantic system colors: primary and secondary labels, window background, separator, and the user's accent. Wallpaper-derived RGB colors appear only in the theme preview. Support light and dark system appearances.

## Typography
SwiftUI system fonts: 20-point semibold app name, 16-point semibold section titles, body controls, caption metadata. Preview code uses system monospaced at 12 points. Do not compress Chinese tracking.

## Components
Native segmented pickers select pages, generation style, and preview appearance. Native bordered buttons provide press and keyboard feedback. Wallpaper image buttons have an accent selection outline and separate accessible favorite controls. Settings use a grouped form. Errors and progress remain inline.

## Layout
Spacing: 4, 8, 12, 16, 20. Default panel 540 by 740 points; minimum 440 by 620. Each page scrolls within its content area. Primary actions stay at the bottom. Image radius 10, preview radius 12. Avoid nested cards around every row.

## Depth
System bar material belongs to navigation and actions. Photography and code previews have one clipping boundary. No decorative translucent cards or custom drop shadows.

## Do and don't
- Show the selected wallpaper beside generation controls.
- Preserve actual Aether output, including its tradeoffs.
- Style selection previews only; applying writes themes.
- Keep targets and low-frequency preferences in Settings.
- Secure entry for the Unsplash key.
- Explain thumbnail previews when originals are unavailable.
- No custom animation for keyboard navigation or palette selection.
- Status messages are not headings.

## Window behavior
At minimum width, thumbnails adapt to fewer columns and form labels wrap. No horizontal scrolling. Short preview code fits the minimum width. At minimum height, content scrolls while navigation and actions remain available. Native controls preserve focus and press feedback; no custom motion.

## Implementation guide
SwiftUI and AppKit only. Navigation: system segmented Picker, 16-point horizontal inset, 8-point control spacing. Images: 10-point clipping radius, caption metadata, 2-point accent selection outline. Code preview: 12-point radius, 16-point padding, monospaced 12-point text, exact generated RGB foreground/background.

