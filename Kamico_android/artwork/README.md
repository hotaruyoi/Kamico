# Launcher artwork

The pink K and portrait form Kamico's launcher artwork. The 512px RGBA source is `launcher-foreground.png`; it is build input and is not declared as a Flutter runtime asset. Android receives five legacy densities and a 432px adaptive foreground with the subject in the central 66/108 area. Windows uses a multi-resolution ICO. PNG compression is lossless after downsampling.

Regenerate platform resources from the client root with `dart tool/generate_brand_icon.dart`; pass another PNG path to replace the source master. Preview output remains local and is excluded from Git.
