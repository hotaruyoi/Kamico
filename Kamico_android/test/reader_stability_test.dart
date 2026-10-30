import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/data/image_size.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/reader.dart';
import 'discovery_test.dart' show apiFor;

/// Page headers must be readable without decoding the bitmap, otherwise the
/// vertical strip cannot reserve a page's extent before its bitmap arrives.
void main() {
  test('image headers expose the page aspect for common formats', () {
    final page = img.Image(width: 200, height: 300);
    for (final (name, bytes) in [
      ('jpeg', img.encodeJpg(page)),
      ('png', img.encodePng(page)),
      ('webp', img.WebPEncoder().encode(page)),
      ('gif', img.encodeGif(page)),
    ]) {
      final size = imageSizeFromBytes(bytes);
      expect(
        size,
        isNotNull,
        reason: '$name header should be readable without a decoder',
      );
      expect(size!.width, 200, reason: name);
      expect(size.height, 300, reason: name);
      expect(imageAspectFromBytes(bytes), closeTo(1.5, .001), reason: name);
    }
  });

  test('files are measured from their header window', () {
    final root = Directory.systemTemp.createTempSync('jm_size_');
    addTearDown(() => root.deleteSync(recursive: true));
    final tall = File('${root.path}/0.img')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 100, height: 250)));
    final wide = File('${root.path}/1.img')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 200, height: 100)));
    expect(measurePageAspects([tall.path, wide.path, '${root.path}/missing']), [
      closeTo(2.5, .001),
      closeTo(.5, .001),
      null,
    ]);
  });

  testWidgets('vertical pages reserve their final height before decoding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    final root = Directory.systemTemp.createTempSync('jm_reader_extent_');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // A decoder may still hold the test page; the temp directory is safe.
      }
    });
    const sizes = [(200, 300), (200, 500), (200, 300)];
    for (var i = 0; i < sizes.length; i++) {
      final (width, height) = sizes[i];
      File('${root.path}/$i.img').writeAsBytesSync(
        img.encodeJpg(img.Image(width: width, height: height)),
      );
    }
    SharedPreferences.setMockInitialValues({'reader_layout': 'vertical'});
    final session = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: apiFor((_) => throw StateError('unexpected network')),
    );
    const comic = Comic(id: '1', title: 'One');
    const chapter = Chapter(id: '10', title: 'Chapter');
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          session: session,
          comic: comic,
          chapter: chapter,
          offline: OfflineChapter(
            comic: comic,
            chapter: chapter,
            folder: root.path,
            count: sizes.length,
          ),
        ),
      ),
    );
    await tester.pump();

    List<double> heights() => [
      for (var i = 0; i < tester.widgetList(find.byType(Image)).length; i++)
        tester.getSize(find.byType(Image).at(i)).height,
    ];
    final reserved = heights();
    debugPrint('reserved on first frame: $reserved');
    expect(
      reserved.length,
      greaterThanOrEqualTo(2),
      reason: 'the vertical strip should render pages immediately',
    );
    final width = tester.getSize(find.byType(Image).first).width;
    // Header measurement runs before the first build, so no page may start at
    // the old fixed 200 placeholder or at the average fallback.
    expect(reserved[0], closeTo(width * 1.5, .5));
    expect(reserved[1], closeTo(width * 2.5, .5));
    expect(reserved.where((height) => height == 200), isEmpty);

    // Decoding the bitmaps must not change the reserved extents.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    final measured = heights();
    expect(measured, reserved);
    expect(tester.takeException(), isNull);

    // Rebuilding the same reader keeps the extents stable as well.
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          session: session,
          comic: comic,
          chapter: chapter,
          offline: OfflineChapter(
            comic: comic,
            chapter: chapter,
            folder: root.path,
            count: sizes.length,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(heights(), reserved);

    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
