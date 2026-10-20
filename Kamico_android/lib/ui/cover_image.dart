import 'package:flutter/material.dart';
import 'cover_image_provider.dart';

class CoverImage extends StatefulWidget {
  const CoverImage({super.key, required this.url});
  final String url;
  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  int _revision = 0;
  int _decodeWidth = 400;
  Future<void> _retry() async {
    await CoverImageProvider(widget.url, _decodeWidth).evict();
    if (mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final pixels = box.maxWidth * MediaQuery.devicePixelRatioOf(context);
      _decodeWidth = pixels.isFinite
          ? ((pixels / 64).ceil() * 64).clamp(64, 400)
          : 400;
      return Image(
        image: CoverImageProvider(widget.url, _decodeWidth),
        key: ValueKey('${widget.url}:$_revision'),
        fit: BoxFit.cover,
        semanticLabel: '作品封面',
        frameBuilder: (context, child, frame, sync) => frame == null
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.image_outlined)),
              )
            : child,
        errorBuilder: (context, error, stack) => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Center(
            child: IconButton(
              tooltip: '封面加载失败，点击重试',
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
      );
    },
  );
}
