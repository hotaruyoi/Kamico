# Launcher artwork

User-supplied pink K and chibi portrait, adapted with the built-in image_gen tool. The compact 512px RGBA source is `launcher-foreground.png`; it is build input and is not declared as a Flutter runtime asset. Android receives five legacy densities and a 432px adaptive foreground with the subject in the central 66/108 area. Windows uses a multi-resolution ICO. PNG compression is lossless after downsampling.

Regenerate platform resources from the client root with `dart tool/generate_brand_icon.dart`; pass another PNG path to replace the source master. Preview output goes to the ignored `docs/previews/1.0.1/` directory.

Generation/edit prompt:

> Use case: background-extraction. Asset type: Android launcher icon foreground. Edit target: the supplied pink letter K and chibi girl PNG. Remove only the outside white background and the faint rounded-square card frame, replacing those areas with actual alpha transparency. Preserve the exact large pink K lettering, girl's face, hair, blue eyes, orange hair clip, hands, pink accent marks, original colors, outlines, halftone texture, and relative composition. Keep the white fills inside the K outline and inside the character opaque. Do not redesign or add anything. Deliver one square image with the complete original K-and-girl composite centered, fully visible, and only a small transparent margin. Edges must remain clean when scaled down as an app icon.
