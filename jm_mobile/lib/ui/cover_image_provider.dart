import 'dart:async';
import 'package:flutter/widgets.dart';

/// Covers have their own LRU so full reader pages cannot evict thumbnails.
final coverImageCache = _CoverImageCache();

class _CoverImageCache extends ImageCache with WidgetsBindingObserver {
  _CoverImageCache() {
    maximumSize = 96;
    maximumSizeBytes = 16 * 1024 * 1024;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didHaveMemoryPressure() => clear();
}

/// Reserve 16 MiB for covers within the existing 100 MiB decoded-image budget.
void configureImageCaching() {
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      100 * 1024 * 1024 - coverImageCache.maximumSizeBytes;
}

class CoverImageProvider extends ResizeImage {
  CoverImageProvider(String url, int decodeWidth)
    : super(NetworkImage(url), width: decodeWidth);

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    ResizeImageKey key,
    ImageErrorListener handleError,
  ) {
    final completer = coverImageCache.putIfAbsent(key, () {
      final result =
          stream.completer ??
          loadImage(
            key,
            PaintingBinding.instance.instantiateImageCodecWithSize,
          );
      result.addEphemeralErrorListener((Object error, StackTrace? stack) {
        scheduleMicrotask(() => coverImageCache.evict(key));
      });
      return result;
    }, onError: handleError);
    if (completer != null && stream.completer == null) {
      stream.setCompleter(completer);
    }
  }

  @override
  Future<bool> evict({
    ImageCache? cache,
    ImageConfiguration configuration = ImageConfiguration.empty,
  }) => super.evict(
    cache: cache ?? coverImageCache,
    configuration: configuration,
  );

  @override
  Future<ImageCacheStatus?> obtainCacheStatus({
    required ImageConfiguration configuration,
    ImageErrorListener? handleError,
  }) async {
    try {
      return coverImageCache.statusForKey(await obtainKey(configuration));
    } catch (error, stack) {
      if (handleError != null) {
        handleError(error, stack);
        return null;
      }
      rethrow;
    }
  }
}
