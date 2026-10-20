import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import 'download_repository.dart';
import 'local_store.dart';

class DownloadJob {
  DownloadJob({
    required this.comic,
    required this.chapter,
    this.state = 'queued',
    this.done = 0,
    this.total = 0,
    this.error = '',
    this.attempts = 0,
  });
  final Comic comic;
  final Chapter chapter;
  String state, error;
  int done, total, attempts;
  String get id => '${comic.key}:${chapter.id}';
  Json toJson() => {
    'comic': comic.toJson(),
    'chapter': {'id': chapter.id, 'title': chapter.title},
    'state': state,
    'done': done,
    'total': total,
    'error': error,
    'attempts': attempts,
  };
  factory DownloadJob.fromJson(Json j) => DownloadJob(
    comic: Comic.fromJson(j['comic'] as Json),
    chapter: Chapter(
      id: '${j['chapter']['id']}',
      title: '${j['chapter']['title']}',
    ),
    state: '${j['state']}',
    done: integer(j['done']),
    total: integer(j['total']),
    error: '${j['error'] ?? ''}',
    attempts: integer(j['attempts']),
  );
}

class DownloadInterrupted implements Exception {}

class EnqueueResult {
  int added = 0, resumed = 0, existing = 0, completed = 0;
  String get message =>
      '新增 $added 章 · 恢复 $resumed 章 · 已在队列 $existing 章 · 已下载 $completed 章';
}

class DownloadQueue extends ChangeNotifier {
  DownloadQueue({
    required this.store,
    required this.repository,
    this.loadChapter,
    this.loadJob,
  });
  final LocalStore store;
  final DownloadRepository repository;
  final Future<ReaderChapter> Function(String)? loadChapter;
  final Future<ReaderChapter> Function(DownloadJob)? loadJob;
  final Map<String, DownloadJob> jobs = {};
  final Set<String> _active = {};
  Future<void> _writes = Future.value();
  bool _disposed = false;
  String? persistenceError;
  Completer<void>? _idle;
  int get concurrency =>
      (store.preferences.getInt('download_concurrency') ?? 2).clamp(1, 3);
  bool get running => _active.isNotEmpty;
  Future<void> get idle =>
      _active.isEmpty && !jobs.values.any((j) => j.state == 'queued')
      ? _writes
      : (_idle ??= Completer<void>()).future;
  Future<void> restore() async {
    for (final entry in store.readMap('download_jobs').entries) {
      try {
        final job = DownloadJob.fromJson(entry.value as Json);
        if (job.state == 'running') job.state = 'queued';
        jobs[job.id] = job;
      } catch (_) {
        continue;
      }
    }
    _changed();
    _pump();
  }

  Future<EnqueueResult> enqueue(Comic comic, List<Chapter> chapters) async {
    final result = EnqueueResult();
    final offline = (await repository.list())
        .map((entry) => '${entry.comic.key}:${entry.chapter.id}')
        .toSet();
    for (final chapter in chapters) {
      final id = '${comic.key}:${chapter.id}';
      final previous = jobs[id];
      if (offline.contains(id)) {
        result.completed++;
        continue;
      }
      if (previous != null && ['running', 'queued'].contains(previous.state)) {
        result.existing++;
        continue;
      }
      if (previous != null) {
        result.resumed++;
        previous.state = 'queued';
        previous.error = '';
        previous.attempts = 0;
      } else {
        result.added++;
        jobs[id] = DownloadJob(comic: comic, chapter: chapter);
      }
    }
    _changed();
    await _writes;
    _pump();
    return result;
  }

  void pause(String id) {
    final job = jobs[id];
    if (job != null && ['running', 'queued'].contains(job.state)) {
      job.state = 'paused';
      _changed();
      _pump();
    }
  }

  void resume(String id) {
    final job = jobs[id];
    if (job != null && !['running', 'done'].contains(job.state)) {
      job.state = 'queued';
      job.error = '';
      job.attempts = 0;
      _changed();
      _pump();
    }
  }

  void cancel(String id) {
    final job = jobs[id];
    if (job != null) {
      job.state = 'cancelled';
      _changed();
      _pump();
    }
  }

  void remove(String id) {
    cancel(id);
    jobs.remove(id);
    _changed();
  }

  void _changed() {
    final data = {for (final e in jobs.entries) e.key: e.value.toJson()};
    _writes = _writes
        .then((_) => store.writeMap('download_jobs', data))
        .catchError((Object error) {
          persistenceError = '下载任务记录保存失败';
          if (!_disposed) notifyListeners();
        });
    if (!_disposed) notifyListeners();
  }

  void _pump() {
    if (_disposed) return;
    for (final job in jobs.values) {
      if (_active.length >= concurrency) break;
      if (job.state == 'queued' && !_active.contains(job.id)) {
        _active.add(job.id);
        unawaited(_run(job));
      }
    }
    if (_active.isEmpty && !jobs.values.any((j) => j.state == 'queued')) {
      final idle = _idle;
      _idle = null;
      if (idle != null) unawaited(_writes.then((_) => idle.complete()));
    }
  }

  void reschedule() => _pump();

  Future<void> _run(DownloadJob job) async {
    job.state = 'running';
    _changed();
    try {
      final reader = await (loadJob?.call(job) ?? loadChapter!(job.chapter.id));
      void checkpoint() {
        if (_disposed || job.state != 'running') throw DownloadInterrupted();
      }

      checkpoint();
      await repository.save(job.comic, job.chapter, reader, (done, total) {
        job.done = done;
        job.total = total;
        _changed();
      }, checkpoint: checkpoint);
      checkpoint();
      job.state = 'done';
      job.error = '';
    } on DownloadInterrupted {
      // Status was already selected by pause/cancel/dispose.
    } catch (e) {
      if (job.state == 'running') {
        job.error = '$e';
        job.attempts++;
        job.state =
            !(e is PlatformException && e.code == 'permission_denied') &&
                job.attempts <=
                    (store.preferences.getInt('download_retries') ?? 2)
            ? 'queued'
            : 'failed';
      }
    } finally {
      _active.remove(job.id);
      _changed();
      _pump();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
