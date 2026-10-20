import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('same local-store call pattern as scrolling cards and chapters', () async {
    final progress = [
      for (var i = 0; i < 1500; i++)
        ReadingProgress(
          comic: Comic(id: '$i', title: 'Book $i'),
          chapterId: '$i',
          page: i,
        ),
    ];
    SharedPreferences.setMockInitialValues({
      'history': jsonEncode(progress.map((e) => e.toJson()).toList()),
      'local_favorites': jsonEncode({
        for (final p in progress)
          p.comic.id: {'comic': p.comic.toJson(), 'folder': '0'},
      }),
      'chapter_progress': jsonEncode({
        for (final p in progress) '${p.comic.id}:${p.chapterId}': p.toJson(),
      }),
    });
    final store = LocalStore(await SharedPreferences.getInstance());
    void work() {
      for (var i = 0; i < 100; i++) {
        expect(store.history.any((p) => p.comic.id == '$i'), true);
        expect(store.localFavorites.containsKey('$i'), true);
        expect(store.chapterProgress('$i', '$i')!.page, i);
      }
    }

    work();
    final times = <int>[];
    for (var i = 0; i < 5; i++) {
      final watch = Stopwatch()..start();
      work();
      watch.stop();
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    debugPrint(
      'LOCAL_STORE_LOOKUPS records=1500 cards=100 runs_us=$times median_us=${times[2]}',
    );
  });
}
