import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import 'aicolor_engine.dart';
import 'download_repository.dart';
import 'image_repository.dart';
import 'local_store.dart';

/// One chapter's colorization task. Persisted, so a queued book survives a
/// restart exactly like the download queue.
class AIColorJob {
  AIColorJob({
    required this.comic,
    required this.chapter,
    this.state = 'queued',
    this.done = 0,
    this.total = 0,
    this.kept = 0,
    this.error = '',
    this.attempts = 0,
  });

  final Comic comic;
  final Chapter chapter;
  String state, error;
  int done, total, attempts;

  /// Pages handed back untouched because they were already colored.
  int kept;

  String get id => '${comic.key}:${chapter.id}';
  bool get active => state == 'running' || state == 'queued';
  double get fraction => total <= 0 ? 0 : done / total;

  String get label => switch (state) {
    'queued' => '等待上色',
    'running' => '上色中',
    'paused' => '已暂停',
    'failed' => '上色失败',
    'done' => '已完成',
    'cancelled' => '已取消',
    _ => state,
  };

  Json toJson() => {
    'comic': comic.toJson(),
    'chapter': {'id': chapter.id, 'title': chapter.title},
    'state': state,
    'done': done,
    'total': total,
    'kept': kept,
    'error': error,
    'attempts': attempts,
  };

  factory AIColorJob.fromJson(Json j) => AIColorJob(
    comic: Comic.fromJson(j['comic'] as Json),
    chapter: Chapter(
      id: '${j['chapter']['id']}',
      title: '${j['chapter']['title']}',
    ),
    state: '${j['state']}',
    done: integer(j['done']),
    total: integer(j['total']),
    kept: integer(j['kept']),
    error: '${j['error']}',
    attempts: integer(j['attempts']),
  );
}

/// Thrown inside [AIColorRepository] when a job was paused or removed while a
/// page conversion was still running.
class AIColorInterrupted implements Exception {}

/// The colorized chapters live in their own library folder, so they never mix
/// with plain downloads and the library can label them apart.
const colorizedLibraryFolder = 'colorized';

/// Background colorization queue.
///
/// One chapter is converted at a time (the model already saturates four cores),
/// and finished chapters are published as ordinary offline chapters. That way
/// the local library, the reader and the PDF exporter all reuse one code path
/// instead of growing a parallel "colorized" mode.
class AIColorRepository extends ChangeNotifier {
  AIColorRepository(
    this._images,
    this.store, {
    AIColorEngine? engine,
    DownloadRepository? output,
    this.loadChapter,
  }) : engine = engine ?? AIColorEngine() {
    // The colorized store must fetch through _fetch: that is the only path
    // that runs inference. Handing in an output built from the plain image
    // loader silently writes the original black-and-white pages.
    //
    // PDFs are left to export time: building one costs about a minute per
    // chapter and would stall the queue right after the last page.
    this.output =
        output ??
        DownloadRepository(
          fetchImage: _fetch,
          folder: colorizedLibraryFolder,
          colorized: true,
          eagerPdf: false,
        );
  }

  /// Resolves the image repository that owns a page. JM and PIC keep separate
  /// caches, so colorizing must read through the same one.
  final ImageRepository Function(ContentSource source) _images;
  final AIColorEngine engine;
  final LocalStore store;
  final Future<ReaderChapter> Function(AIColorJob job)? loadChapter;

  late final DownloadRepository output;

  final Map<String, AIColorJob> jobs = {};

  Future<void> _writes = Future.value();
  Completer<void>? _idle;
  bool _disposed = false;
  AIColorJob? _current;

  /// Surfaced on the download screen when job bookkeeping cannot be saved.
  String? persistenceError;

  AIColorQuality _quality = AIColorQuality.balanced;
  AIColorQuality get quality => _quality;

  bool get running => _current != null;
  bool get supported => engine.supported;
  AIColorJob? get current => _current;

  int get queued => jobs.values.where((j) => j.state == 'queued').length;
  int get finished => jobs.values.where((j) => j.state == 'done').length;

  Future<void> get idle {
    if (_current == null && queued == 0) return _writes;
    return (_idle ??= Completer<void>()).future;
  }

  void setQuality(AIColorQuality value) {
    if (_quality == value) return;
    _quality = value;
    notifyListeners();
  }

  Future<void> restore() async {
    for (final entry in store.readMap('aicolor_jobs').entries) {
      try {
        final job = AIColorJob.fromJson(entry.value as Json);
        // A process that died mid-chapter leaves this flag behind.
        if (job.state == 'running') job.state = 'queued';
        jobs[entry.key] = job;
      } catch (_) {
        continue;
      }
    }
    await _migrateLibrary();
    _changed();
    _pump();
  }

  /// Version 2 is the first release whose chapters really are colorized.
  /// Anything the earlier build left behind is a plain black-and-white copy
  /// carrying a `colorized` flag, so it has to go rather than linger forever.
  static const int _libraryVersion = 2;

  Future<void> _migrateLibrary() async {
    final stored = store.preferences.getInt('aicolor_library_version') ?? 1;
    if (stored >= _libraryVersion) return;
    try {
      final directory = await output.directory;
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      // A library that cannot be read is already effectively empty.
    }
    jobs.removeWhere((_, job) => job.state == 'done');
    await store.preferences.setInt('aicolor_library_version', _libraryVersion);
  }

  /// Queues chapters of one book. Already colorized, queued or running
  /// chapters are skipped, so tapping the button twice is harmless.
  Future<AIColorEnqueueResult> enqueue(Comic comic, List<Chapter> chapters) async {
    final done = (await output.list())
        .map((entry) => '${entry.comic.key}:${entry.chapter.id}')
        .toSet();
    final result = AIColorEnqueueResult();
    for (final chapter in chapters) {
      final id = '${comic.key}:${chapter.id}';
      if (done.contains(id)) {
        result.completed++;
        continue;
      }
      final previous = jobs[id];
      if (previous != null && previous.active) {
        result.existing++;
        continue;
      }
      if (previous != null) {
        previous
          ..state = 'queued'
          ..error = ''
          ..done = 0
          ..total = 0
          ..kept = 0
          ..attempts = 0;
        result.resumed++;
        continue;
      }
      jobs[id] = AIColorJob(comic: comic, chapter: chapter);
      result.added++;
    }
    _changed();
    await _writes;
    _pump();
    return result;
  }

  void pause(String id) {
    final job = jobs[id];
    if (job == null || job.state != 'queued') return;
    job.state = 'paused';
    _changed();
    _pump();
  }

  void resume(String id) {
    final job = jobs[id];
    if (job == null || job.state != 'paused') return;
    job
      ..state = 'queued'
      ..error = ''
      ..attempts = 0;
    _changed();
    _pump();
  }

  void cancel(String id) {
    final job = jobs[id];
    if (job == null) return;
    job
      ..state = 'cancelled'
      ..error = '';
    if (!identical(job, _current)) _changed();
    _pump();
  }

  void remove(String id) {
    if (jobs.remove(id) == null) return;
    _changed();
    _pump();
  }

  void pauseAll() {
    for (final job in jobs.values) {
      if (job.state == 'queued') job.state = 'paused';
    }
    _changed();
    _pump();
  }

  void resumeAll() {
    for (final job in jobs.values) {
      if (job.state == 'paused') {
        job
          ..state = 'queued'
          ..error = ''
          ..attempts = 0;
      }
    }
    _changed();
    _pump();
  }

  /// Drops finished and cancelled bookkeeping; the library itself is untouched.
  void clearFinished() {
    jobs.removeWhere(
      (_, job) => job.state == 'done' || job.state == 'cancelled',
    );
    _changed();
  }

  void _changed() {
    final data = {for (final e in jobs.entries) e.key: e.value.toJson()};
    _writes = _writes
        .then((_) => store.writeMap('aicolor_jobs', data))
        .catchError((Object error) {
          persistenceError = '上色任务记录保存失败';
          if (!_disposed) notifyListeners();
        });
    if (!_disposed) notifyListeners();
  }

  void _pump() {
    if (_disposed || _current != null) return;
    for (final job in jobs.values) {
      if (job.state != 'queued') continue;
      if (!engine.supported) {
        job
          ..state = 'failed'
          ..error = '当前设备不支持 AI 上色';
        _changed();
        continue;
      }
      unawaited(_run(job));
      return;
    }
    if (_current == null && queued == 0) {
      final idle = _idle;
      _idle = null;
      if (idle != null) unawaited(_writes.then((_) => idle.complete()));
    }
  }

  void reschedule() => _pump();

  Future<void> _run(AIColorJob job) async {
    _current = job;
    job
      ..state = 'running'
      ..done = 0
      ..total = 0
      ..kept = 0;
    _changed();
    try {
      final reader = await (loadChapter?.call(job) ??
          Future<ReaderChapter>.error(
            const AIColorException('无法读取章节内容'),
          ));
      void checkpoint() {
        if (_disposed || job.state != 'running') throw AIColorInterrupted();
      }

      checkpoint();
      await output.save(
        job.comic,
        job.chapter,
        reader,
        (done, total) {
          job
            ..done = done
            ..total = total;
          _changed();
        },
        checkpoint: checkpoint,
      );
      checkpoint();
      job.error = '';
      job.state = 'done';
    } on AIColorInterrupted {
      // pause()/remove() already set the state we want.
    } catch (e) {
      if (job.state == 'running') {
        job.error = e is AIColorException ? e.message : '$e';
        job.attempts++;
        final retries = store.preferences.getInt('aicolor_retries') ?? 1;
        job.state = job.attempts <= retries ? 'queued' : 'failed';
      }
    } finally {
      _current = null;
      _changed();
      _pump();
    }
  }

  Future<Uint8List> _fetch(ReaderChapter reader, int index) async {
    final source = _images(reader.source);
    final original = await source.load(reader, index);
    final aspect = source.aspectFor(reader, index) ?? 1.45;
    final result = await engine.colorize(
      original,
      quality: _quality,
      aspect: aspect,
    );
    // A page that is already colored comes back untouched; counting it keeps
    // the summary honest instead of claiming everything was repainted.
    if (result.alreadyColored) _current?.kept++;
    return result.bytes;
  }

  /// Total bytes of the colorized library on disk.
  Future<int> cacheBytes() => output.bytes;

  /// Deletes every colorized chapter. Only ever reached from a confirmation.
  Future<void> clearLibrary() async {
    for (final job in jobs.values) {
      if (job.active) job.state = 'cancelled';
    }
    _changed();
    for (final chapter in await output.list()) {
      try {
        await output.delete(chapter);
      } catch (_) {
        continue;
      }
    }
    jobs.removeWhere(
      (_, job) => job.state == 'done' || job.state == 'cancelled',
    );
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// What [AIColorRepository.enqueue] did, worded like the download queue.
class AIColorEnqueueResult {
  int added = 0, resumed = 0, existing = 0, completed = 0;
  String get message =>
      '新增 $added 章 · 恢复 $resumed 章 · 已在队列 $existing 章 · 已上色 $completed 章';
}
