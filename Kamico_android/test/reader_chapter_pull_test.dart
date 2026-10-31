import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/reader.dart';
import 'discovery_test.dart' show apiFor;

/// Reaching the end of a chapter and pulling further along the reading
/// direction fills a ring; filling it opens the neighbouring chapter. The
/// overlay must stay out of the page layout, and the pull must not appear when
/// there is no chapter to reach.
void main() {
  const surface = ValueKey('reader-tap-surface');
  const ring = ValueKey('chapter-pull-ring');
  const blank = ValueKey('chapter-pull-blank');
  const label = ValueKey('chapter-pull-label');

  Future<Directory> pages(int count) async {
    final root = Directory.systemTemp.createTempSync('jm_chapter_pull_');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // A decoder may still hold the test page; the temp directory is safe.
      }
    });
    for (var i = 0; i < count; i++) {
      File('${root.path}/$i.img').writeAsBytesSync(
        img.encodeJpg(img.Image(width: 200, height: 300)),
      );
    }
    return root;
  }

  Future<AppSession> sessionFor(String layout) async {
    SharedPreferences.setMockInitialValues({'reader_layout': layout});
    return AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: apiFor((_) => throw StateError('unexpected network')),
    );
  }

  Future<void> show(
    WidgetTester tester,
    AppSession session,
    Directory root, {
    int page = 1,
    int count = 2,
    bool neighbours = true,
    int chapterIndex = 0,
  }) async {
    const comic = Comic(id: '1', title: 'One');
    const chapters = [
      Chapter(id: '10', title: 'Chapter'),
      Chapter(id: '11', title: 'Next'),
    ];
    final chapter = chapters[chapterIndex];
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          session: session,
          comic: comic,
          chapter: chapter,
          initialPage: page,
          chapters: neighbours ? chapters : [chapter],
          offline: OfflineChapter(
            comic: comic,
            chapter: chapter,
            folder: root.path,
            count: count,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  double? ringValue(WidgetTester tester) {
    final found = find.byKey(ring);
    if (found.evaluate().isEmpty) return null;
    return (tester.widget(found) as CircularProgressIndicator).value;
  }

  Future<TestGesture> pull(
    WidgetTester tester,
    Offset step,
    int frames,
  ) async {
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(surface)));
    for (var i = 0; i < frames; i++) {
      await gesture.moveBy(step);
      await tester.pump(const Duration(milliseconds: 16));
    }
    return gesture;
  }

  Future<void> close(WidgetTester tester, AppSession session) async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  }

  testWidgets('the last page fills the ring before it reaches the halfway '
      'point', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final root = await pages(2);
    final session = await sessionFor('vertical');
    await show(tester, session, root);

    // Each 30px frame is 30 / (viewport / 2) of the ring, so five frames land
    // near a third of the way without crossing the halfway trigger.
    final gesture = await pull(tester, const Offset(0, -30), 5);
    expect(ringValue(tester), isNotNull);
    expect(ringValue(tester), greaterThan(.1));
    expect(ringValue(tester), lessThan(.9));
    expect(find.byKey(blank), findsOneWidget);
    expect(find.byKey(label), findsOneWidget);
    expect(find.text('继续阅读下一章'), findsOneWidget);

    // The blank band grows with the pull instead of shifting the pages.
    final band = tester.getSize(find.byKey(blank)).height;
    expect(band, greaterThan(0));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(ring), findsNothing);
    expect(find.byKey(blank), findsNothing);
    expect(tester.takeException(), isNull);
    await close(tester, session);
  });

  testWidgets('the ring grows as the finger keeps pulling', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final root = await pages(2);
    final session = await sessionFor('vertical');
    await show(tester, session, root);

    final gesture = await pull(tester, const Offset(0, -30), 3);
    final early = ringValue(tester)!;
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final later = ringValue(tester)!;
    expect(later, greaterThan(early));

    // Dragging back retracts the ring rather than keeping the peak value.
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(ringValue(tester), isNull);
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await close(tester, session);
  });

  testWidgets('filling the ring hands over to the next chapter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final root = await pages(2);
    final session = await sessionFor('vertical');
    await show(tester, session, root);

    final gesture = await pull(tester, const Offset(0, -30), 30);
    expect(ringValue(tester), isNull, reason: 'the ring resets on trigger');
    await gesture.up();
    await tester.pump();

    // Filling the ring hands over to the neighbouring chapter; the offline
    // test reader has no such chapter, so the switch stops auto-reading and
    // reports it instead of silently staying put.
    expect(find.text('切换章节，自动阅读已停止'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester, session);
  });

  testWidgets('the first page pulls backwards to the previous chapter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final root = await pages(2);
    final session = await sessionFor('vertical');
    await show(tester, session, root, page: 0, chapterIndex: 1);

    final gesture = await pull(tester, const Offset(0, 30), 5);
    expect(ringValue(tester), isNotNull);
    expect(find.text('继续阅读上一章'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await close(tester, session);
  });

  testWidgets('left-to-right paging fills the ring when pulling left', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final root = await pages(2);
    final session = await sessionFor('pages');
    await show(tester, session, root);

    final gesture = await pull(tester, const Offset(-30, 0), 3);
    expect(ringValue(tester), isNotNull);
    expect(ringValue(tester), greaterThan(0));
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await close(tester, session);
  });

  testWidgets('right-to-left paging fills the ring when pulling right', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final root = await pages(2);
    final session = await sessionFor('reversePages');
    await show(tester, session, root);

    final gesture = await pull(tester, const Offset(30, 0), 3);
    expect(ringValue(tester), isNotNull);
    expect(ringValue(tester), greaterThan(0));
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await close(tester, session);
  });

  Offset contentShift(WidgetTester tester) {
    final found = find.byKey(const ValueKey('chapter-pull-content'));
    final matrix = tester.widget<Transform>(found).transform;
    return Offset(matrix.storage[12], matrix.storage[13]);
  }

  Rect bandRect(WidgetTester tester) {
    return tester.getRect(find.byKey(blank));
  }

  /// The reader viewport in logical pixels. `getRect` on anything inside the
  /// pull layer reports the shifted position, so the edges have to come from
  /// the view itself.
  Rect viewRect(WidgetTester tester) {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    return Offset.zero & size;
  }

  testWidgets('the page follows the finger and the band opens behind it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final root = await pages(2);
    final session = await sessionFor('vertical');
    await show(tester, session, root);

    final before = contentShift(tester);
    expect(before, Offset.zero);

    final gesture = await pull(tester, const Offset(0, -30), 6);
    final shift = contentShift(tester);
    // The page travels upwards with the finger instead of staying put while a
    // mask grows over it.
    expect(shift.dy, lessThan(-40));
    expect(shift.dx, 0);

    // The vacated band sits at the bottom edge and grows with the pull, so it
    // is never painted over a page.
    final band = bandRect(tester);
    expect(band.bottom, moreOrLessEquals(viewRect(tester).bottom, epsilon: 1));
    expect(band.height, moreOrLessEquals(-shift.dy, epsilon: 1));

    await gesture.up();
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(contentShift(tester), Offset.zero);
    expect(tester.takeException(), isNull);
    await close(tester, session);
  });

  testWidgets('pulling back retracts the band instead of leaving it painted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final root = await pages(2);
    final session = await sessionFor('vertical');
    await show(tester, session, root);

    final gesture = await pull(tester, const Offset(0, -30), 6);
    final peak = -contentShift(tester).dy;
    expect(peak, greaterThan(0));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(-contentShift(tester).dy, lessThan(peak));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    await close(tester, session);
  });

  testWidgets('left-to-right paging opens the band on the right edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final root = await pages(2);
    final session = await sessionFor('pages');
    await show(tester, session, root);

    final gesture = await pull(tester, const Offset(-30, 0), 4);
    final shift = contentShift(tester);
    // The page slides left with the finger and the band opens on the right.
    expect(shift.dx, lessThan(0));
    expect(shift.dy, 0);
    final band = bandRect(tester);
    expect(band.right, moreOrLessEquals(viewRect(tester).right, epsilon: 1));
    expect(band.width, moreOrLessEquals(-shift.dx, epsilon: 1));
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await close(tester, session);
  });

  testWidgets('the hint waits for room and then stays inside the band', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final root = await pages(2);
    final session = await sessionFor('pages');
    await show(tester, session, root);

    // A narrow band is a full-height column. Painting the hint across it would
    // spill white glyphs onto the white page, so the ring holds the column
    // alone until there is room for the text.
    final gesture = await pull(tester, const Offset(-30, 0), 2);
    var band = bandRect(tester);
    final circle = tester.getRect(find.byKey(ring));
    expect(circle.left, greaterThanOrEqualTo(band.left - 0.5));
    expect(circle.right, lessThanOrEqualTo(band.right + 0.5));
    expect(find.byKey(label), findsNothing);

    // Once the column is wide enough the hint joins the ring, still inside it.
    for (var i = 0; i < 2; i++) {
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    band = bandRect(tester);
    final text = tester.getRect(find.byKey(label));
    expect(text.left, greaterThanOrEqualTo(band.left - 0.5));
    expect(text.right, lessThanOrEqualTo(band.right + 0.5));
    expect(text.width, lessThanOrEqualTo(band.width));
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await close(tester, session);
  });

  testWidgets('right-to-left paging opens the band on the left edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final root = await pages(2);
    final session = await sessionFor('reversePages');
    await show(tester, session, root);

    final gesture = await pull(tester, const Offset(30, 0), 4);
    final shift = contentShift(tester);
    // "Next chapter" runs rightwards here, so the page moves right and the
    // band that opens behind it is on the left. Deriving the side from the
    // chapter direction alone would paint it on the wrong edge.
    expect(shift.dx, greaterThan(0));
    final band = bandRect(tester);
    expect(band.left, moreOrLessEquals(viewRect(tester).left, epsilon: 1));
    expect(band.width, moreOrLessEquals(shift.dx, epsilon: 1));
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await close(tester, session);
  });

  testWidgets('page extent is untouched while the pull is in flight', (
    tester,
  ) async {
    // docs/BUG_READER_JITTER.md: a vertical page that changes extent after it
    // is laid out shifts every page above it. The pull must be paint-only, so
    // the laid out size has to stay identical to the resting one.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final root = await pages(3);
    final session = await sessionFor('vertical');
    await show(tester, session, root, page: 2, count: 3);

    final content = find.byKey(const ValueKey('chapter-pull-content'));
    final resting = tester.getSize(content);
    final indexBefore = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;

    final gesture = await pull(tester, const Offset(0, -30), 8);
    expect(tester.getSize(content), resting);
    final offsetDuring = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(offsetDuring, indexBefore);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    await close(tester, session);
  });

  testWidgets('nothing appears when the chapter has no neighbour', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final root = await pages(2);
    final session = await sessionFor('vertical');
    await show(tester, session, root, neighbours: false);

    final gesture = await pull(tester, const Offset(0, -30), 20);
    expect(find.byKey(ring), findsNothing);
    expect(find.byKey(blank), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await close(tester, session);
  });
}
