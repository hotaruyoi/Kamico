import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:path_provider/path_provider.dart';

/// Thrown when the native colorizer cannot run. Its message is user facing.
class AIColorException implements Exception {
  const AIColorException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Quality tiers. The value is the page's short edge in pixels; the long edge
/// follows the page aspect ratio (a 2:3 page maps to 384×576, 512×768 and
/// 640×960, which is exactly what the on-device benchmarks measured).
enum AIColorQuality {
  fast('快速', 384, '约 2 秒/页，内存约 350MB'),
  balanced('均衡', 512, '约 3.5 秒/页，内存约 490MB'),
  fine('精细', 640, '约 5 秒/页，内存约 1GB，建议 12GB 机型');

  const AIColorQuality(this.label, this.longEdge, this.hint);
  final String label;
  final int longEdge;
  final String hint;

  static AIColorQuality fromName(String? name) => AIColorQuality.values
      .firstWhere((q) => q.name == name, orElse: () => AIColorQuality.balanced);
}

/// Result of one page colorization.
class AIColorResult {
  const AIColorResult(
    this.bytes,
    this.width,
    this.height, {
    this.alreadyColored = false,
  });
  final Uint8List bytes;
  final int width;
  final int height;

  /// True when the page was already in color and the pipeline returned it
  /// unchanged instead of repainting it.
  final bool alreadyColored;
}

// ---------------------------------------------------------------------------
// FFI surface
// ---------------------------------------------------------------------------

typedef _InitNative =
    Int32 Function(
      Pointer<Utf8> modelPath,
      Int32 threads,
      Int32 useArena,
      Pointer<Uint8> error,
      Int32 errorCapacity,
    );
typedef _InitDart =
    int Function(
      Pointer<Utf8>,
      int,
      int,
      Pointer<Uint8>,
      int,
    );

typedef _RunNative =
    Int32 Function(
      Pointer<Uint8> input,
      Int32 inputLength,
      Int32 targetWidth,
      Int32 targetHeight,
      Int32 quality,
      Pointer<Pointer<Uint8>> output,
      Pointer<Int32> outputLength,
      Pointer<Int32> alreadyColored,
      Pointer<Uint8> error,
      Int32 errorCapacity,
    );
typedef _RunDart =
    int Function(
      Pointer<Uint8>,
      int,
      int,
      int,
      int,
      Pointer<Pointer<Uint8>>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Uint8>,
      int,
    );

typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);
typedef _BoolNative = Int32 Function();
typedef _BoolDart = int Function();

class _Native {
  _Native(DynamicLibrary lib)
    : init = lib.lookupFunction<_InitNative, _InitDart>('aicolor_init'),
      run = lib.lookupFunction<_RunNative, _RunDart>('aicolor_run'),
      free = lib.lookupFunction<_FreeNative, _FreeDart>('aicolor_free'),
      dispose = lib.lookupFunction<Void Function(), void Function()>(
        'aicolor_dispose',
      ),
      ready = lib.lookupFunction<_BoolNative, _BoolDart>('aicolor_is_ready');

  final _InitDart init;
  final _RunDart run;
  final _FreeDart free;
  final void Function() dispose;
  final _BoolDart ready;
}

_Native? _open() {
  // The stub build (non arm64) loads fine but reports "unsupported".
  if (!Platform.isAndroid && !Platform.isLinux) return null;
  try {
    return _Native(DynamicLibrary.open('libaicolor.so'));
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Isolate entry point
// ---------------------------------------------------------------------------

class _NativeJob {
  const _NativeJob({
    required this.modelPath,
    required this.threads,
    required this.useArena,
    required this.input,
    required this.width,
    required this.height,
    required this.jpegQuality,
  });

  final String modelPath;
  final int threads;
  final bool useArena;
  final Uint8List input;
  final int width;
  final int height;
  final int jpegQuality;
}

class _NativeOutcome {
  const _NativeOutcome(this.bytes, this.error, {this.alreadyColored = false});
  final Uint8List? bytes;
  final String? error;
  final bool alreadyColored;
}

const int _errorCapacity = 512;

String _readError(Pointer<Uint8> buffer) {
  final text = buffer.cast<Utf8>().toDartString();
  return text.isEmpty ? '未知错误' : text;
}

_NativeOutcome _runNative(_NativeJob job) {
  final api = _open();
  if (api == null) {
    return const _NativeOutcome(null, '当前设备不支持 AI 上色');
  }
  final error = calloc<Uint8>(_errorCapacity);
  try {
    if (api.ready() == 0) {
      final path = job.modelPath.toNativeUtf8();
      try {
        final code = api.init(
          path,
          job.threads,
          job.useArena ? 1 : 0,
          error,
          _errorCapacity,
        );
        if (code != 0) {
          final text = _readError(error);
          return _NativeOutcome(
            null,
            code == -2 ? '当前设备不支持 AI 上色' : '上色引擎初始化失败：$text',
          );
        }
      } finally {
        malloc.free(path);
      }
    }
    final inputPointer = calloc<Uint8>(job.input.length);
    final outPointer = calloc<Pointer<Uint8>>();
    final outLength = calloc<Int32>();
    final colored = calloc<Int32>();
    try {
      inputPointer.asTypedList(job.input.length).setAll(0, job.input);
      final code = api.run(
        inputPointer,
        job.input.length,
        job.width,
        job.height,
        job.jpegQuality,
        outPointer,
        outLength,
        colored,
        error,
        _errorCapacity,
      );
      if (code != 0) {
        return _NativeOutcome(
          null,
          code == -2 ? '当前设备不支持 AI 上色' : '上色失败：${_readError(error)}',
        );
      }
      final length = outLength.value;
      final pointer = outPointer.value;
      if (pointer == nullptr || length <= 0) {
        return const _NativeOutcome(null, '上色失败：没有输出图像');
      }
      try {
        return _NativeOutcome(
          Uint8List.fromList(pointer.asTypedList(length)),
          null,
          alreadyColored: colored.value != 0,
        );
      } finally {
        api.free(pointer.cast<Void>());
      }
    } finally {
      calloc.free(inputPointer);
      calloc.free(outPointer);
      calloc.free(outLength);
      calloc.free(colored);
    }
  } catch (e) {
    return _NativeOutcome(null, '上色失败：$e');
  } finally {
    calloc.free(error);
  }
}

// ---------------------------------------------------------------------------
// Public engine
// ---------------------------------------------------------------------------

/// Runs the bundled colorization model through the native pipeline.
///
/// The model asset is copied to the app support directory on first use because
/// ONNX Runtime loads it from a real path; the copy is 32 MB and happens once.
class AIColorEngine {
  AIColorEngine({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const _assetPath = 'assets/models/manga-colorize-qdq.ort';
  static const _assetKey = 'manga-colorize-qdq.ort';

  final AssetBundle _bundle;
  String? _modelPath;
  int? _totalRamMb;

  bool get supported => Platform.isAndroid;

  /// Threads are capped at four: the big cores of current phones number four,
  /// and measured throughput drops beyond that.
  int get threads => 4;

  /// The memory arena is ~33% faster but roughly doubles the peak, so it is
  /// only enabled on devices with enough headroom.
  bool get useArena => (_totalRamMb ?? _readTotalRamMb()) >= 6000;

  int _readTotalRamMb() {
    var total = 0;
    try {
      final text = File('/proc/meminfo').readAsStringSync();
      final match = RegExp(r'MemTotal:\s+(\d+) kB').firstMatch(text);
      if (match != null) {
        total = int.parse(match.group(1)!) ~/ 1024;
      }
    } catch (_) {
      total = 0;
    }
    _totalRamMb = total;
    return total;
  }

  /// Copies the model out of the asset bundle once and returns its path.
  Future<String> prepare() async {
    final cached = _modelPath;
    if (cached != null) return cached;
    final directory = await getApplicationSupportDirectory();
    final models = Directory('${directory.path}/models');
    await models.create(recursive: true);
    final file = File('${models.path}/$_assetKey');
    final data = await _bundle.load(_assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return _modelPath = file.path;
  }

  /// The tier value is the page's short edge; the long edge follows the page
  /// aspect ratio. Both are rounded to a multiple of 32, which the network
  /// requires for its concat/skip connections. A 2:3 page therefore maps to
  /// 384×576, 512×768 and 640×960, matching the measured benchmarks.
  static ({int width, int height}) targetSize(
    AIColorQuality quality,
    double aspect,
  ) {
    final short = quality.longEdge;
    final safeAspect = aspect.isFinite && aspect > 0 ? aspect : 1.45;
    final scaled = safeAspect.clamp(0.5, 3.0);
    final long = ((short * scaled) / 32).round() * 32;
    final maxLong = 2048;
    final clamped = long > maxLong ? maxLong : long;
    return scaled >= 1
        ? (width: short, height: clamped)
        : (width: clamped, height: short);
  }

  /// Colorizes one encoded page and returns an encoded JPEG.
  Future<AIColorResult> colorize(
    Uint8List encoded, {
    required AIColorQuality quality,
    required double aspect,
    int jpegQuality = 92,
  }) async {
    if (!supported) {
      throw const AIColorException('AI 上色目前只支持 Android');
    }
    final model = await prepare();
    final size = targetSize(quality, aspect);
    final job = _NativeJob(
      modelPath: model,
      threads: threads,
      useArena: useArena,
      input: encoded,
      width: size.width,
      height: size.height,
      jpegQuality: jpegQuality,
    );
    final outcome = await Isolate.run(() => _runNative(job));
    final bytes = outcome.bytes;
    if (bytes == null) {
      throw AIColorException(outcome.error ?? '上色失败');
    }
    return AIColorResult(
      bytes,
      size.width,
      size.height,
      alreadyColored: outcome.alreadyColored,
    );
  }
}
