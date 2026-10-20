import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';

/// One decoded frame drives both the portrait and its blurred backdrop.
class DetailArtwork extends ChangeNotifier {
  ImageStream? _stream;
  ImageProvider? _provider;
  ImageConfiguration? _configuration;
  ImageInfo? _frame;
  Object? error;
  bool _disposed = false, _retrying = false;
  int _generation = 0;
  ImageInfo? get frame => _frame;
  late final _listener = ImageStreamListener(
    (frame, sync) {
      if (_disposed) {
        frame.dispose();
        return;
      }
      _replace(frame);
      error = null;
      notifyListeners();
    },
    onError: (Object failure, StackTrace? stack) {
      if (_disposed) return;
      error = failure;
      notifyListeners();
    },
  );

  void resolve(ImageProvider provider, ImageConfiguration configuration) {
    if (_disposed) return;
    final next = provider.resolve(configuration);
    if (_stream?.key == next.key) return;
    _generation++;
    _stream?.removeListener(_listener);
    _provider = provider;
    _configuration = configuration;
    _stream = next;
    _replace(null);
    error = null;
    next.addListener(_listener);
  }

  Future<void> retry() async {
    final provider = _provider, configuration = _configuration;
    if (_disposed || _retrying || provider == null || configuration == null) {
      return;
    }
    _retrying = true;
    final generation = _generation;
    try {
      await provider.evict(configuration: configuration);
      if (_disposed || generation != _generation) return;
      _stream?.removeListener(_listener);
      _stream = null;
      resolve(provider, configuration);
      notifyListeners();
    } finally {
      _retrying = false;
    }
  }

  void _replace(ImageInfo? frame) {
    final previous = _frame;
    _frame = frame;
    if (previous != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stream?.removeListener(_listener);
    _replace(null);
    super.dispose();
  }
}
