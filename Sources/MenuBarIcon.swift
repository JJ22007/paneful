import AppKit

/// The menu bar icon: Lucide's `layout-panel-left` (https://lucide.dev, ISC licence, see
/// LICENSES/lucide.txt), drawn as a template image so macOS tints it for light and dark menu bars.
func menuBarIcon(size: CGFloat = 18) -> NSImage {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" \
    stroke="black" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">\
    <rect width="7" height="18" x="3" y="3" rx="1"/><rect width="7" height="7" x="14" y="3" rx="1"/>\
    <rect width="7" height="7" x="14" y="14" rx="1"/></svg>
    """
    let image = NSImage(data: Data(svg.utf8)) ?? NSImage()
    image.size = NSSize(width: size, height: size)
    image.isTemplate = true
    image.accessibilityDescription = "Paneful"
    return image
}
