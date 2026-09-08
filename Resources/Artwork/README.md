# Application icon

`AppIcon-Source.png` is the current 1254 × 1254 PNG with real alpha transparency, generated using the built-in image generation tool on 2026-09-09. It represents a merged window zone beside two stacked zones, with blue/cyan panes on a dark rounded tile. The original blue design was restored at the user’s request; `AppIcon-Blue.png` preserves it, and `AppIcon-Graphite.png` archives the optional monochrome variant.

Run `./scripts/build-icon.sh` from the repository root to regenerate `Resources/AppIcon.icns`. The ordinary build runs this automatically when needed. Apple's `sips` and `iconutil` create every standard 16–512-point icon size at 1× and 2×, including the 1024-pixel representation. The source artwork is not bundled into the app. The app, menu bar, and settings sidebar share this asset. The menu image is a cached 18-point non-template image, preserving its colors and shading without continuous rendering.

## Archived monochrome edit prompt

Reference: `AppIcon-Blue.png`.

Recolor this app icon to dark monochrome: charcoal black outer tile, silver gray tall left pane, darker graphite two right panes, subtle white highlights. Same icon, same shape and layout, no text. Transparent background, isolated icon PNG with alpha, background removed.

## Original generation prompt

Use case: logo-brand. Asset type: production macOS application icon for Not Fancy Zones, a very lightweight native window zoning utility. Generate one polished 1024 x 1024 square icon, straight-on, no presentation mockup. A beautifully proportioned macOS rounded-square tile occupying about 82% of the canvas, centered with even transparent padding outside its silhouette. Inside a deep midnight blue softly beveled tile, exactly THREE substantial inset rounded rectangular panes arranged like a window zoning layout: one large tall pane on the left occupying two-thirds of the interior width and spanning both rows, and two smaller equal panes stacked on the right. Consistent generous dark gutters, precise aligned edges and generous internal padding. This clear asymmetric 2:1 grid is the entire symbol. Quiet luminous blue and cool cyan pane surfaces with subtle frosted-glass depth and restrained soft highlights; the left pane is brighter cyan-blue and the right panes slightly darker blue. Refined native macOS utility aesthetic, confident and simple, legible at 32px. Rounded corners have a deliberate consistent hierarchy. Gentle dimensionality, crisp silhouette, balanced optical weight; no busy reflections or heavy drop shadow. Genuinely transparent alpha outside the rounded-square tile; no checkerboard drawn into the artwork. No text, no letters, no numbers, no mouse cursor, no arrows, no monitor stand, no additional objects, no border around the canvas. Deliver only the single finished icon.
