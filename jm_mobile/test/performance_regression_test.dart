import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/cover_image.dart';
import 'package:jm_mobile/ui/discovery.dart';
import 'discovery_test.dart' show apiFor;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'discovery scroll does not reconstruct visible cards when width is unchanged',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor(
          (_) => [
            for (var group = 0; group < 3; group++)
              {
                'title': 'Group $group',
                'type': 'promote',
                'content': [
                  for (var i = 0; i < 6; i++)
                    {'id': '${group * 6 + i}', 'name': 'Book $i'},
                ],
              },
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DiscoveryScreen(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      final first = find.byWidgetPredicate(
        (widget) => widget is ComicCard && widget.comic.id == '0',
      );
      final before = tester.widget<ComicCard>(first);
      final gesture = await tester.startGesture(const Offset(195, 500));
      await gesture.moveBy(const Offset(0, -120));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 200));
      final offset = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .pixels;
      final after = tester.widget<ComicCard>(first);
      await gesture.up();
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(700, 844);
      await tester.pumpAndSettle();
      final resized = tester.widget<ComicCard>(first);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      expect(offset, greaterThan(0));
      expect(
        identical(before, after),
        isTrue,
        reason:
            'Scrolling alone must not rebuild existing visible cards during sliver layout',
      );
      expect(
        identical(after, resized),
        isFalse,
        reason: 'Width changes must still rebuild the responsive grid',
      );
    },
  );
  testWidgets(
    'small covers decode for their physical display width instead of every thumbnail at 400px',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 48,
              height: 72,
              child: CoverImage(url: 'https://example.test/cover.jpg'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final provider =
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      expect(provider.width, lessThanOrEqualTo(128));
      expect(provider.width, greaterThanOrEqualTo(96));
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'scrolling card and chapter lookups reuse immutable decoded snapshots until the underlying preference changes',
    () async {
      const comic = Comic(id: '1', title: 'One');
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
        'chapter_progress': jsonEncode({
          for (final p in progress) '${p.comic.id}:${p.chapterId}': p.toJson(),
        }),
        'local_favorites': jsonEncode({
          for (final p in progress)
            p.comic.id: {'comic': p.comic.toJson(), 'folder': '0'},
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      expect(
        identical(store.history, store.history),
        true,
        reason:
            'Visible cards must not parse and allocate the entire history again',
      );
      expect(identical(store.localFavorites, store.localFavorites), true);
      expect(
        identical(
          store.chapterProgress('1', '1'),
          store.chapterProgress('1', '1'),
        ),
        true,
      );
      await store.saveProgress(
        const ReadingProgress(comic: comic, chapterId: '1', page: 9),
      );
      expect(store.chapterProgress('1', '1')!.page, 9);
      await prefs.setString('history', '[]');
      expect(store.history, isEmpty);
      await store.moveLocal(['1'], '0');
      expect(store.localFavorites['1']!['folder'], '0');
      await store.removeLocal(['1']);
      expect(store.localFavorites.containsKey('1'), false);
    },
  );

  testWidgets(
    'reading progress does not reconstruct MaterialApp and themes; appearance updates still apply',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((_) => []),
      );
      await tester.pumpWidget(JmApp(session: session));
      await tester.pumpAndSettle();
      final before = tester.widget<MaterialApp>(find.byType(MaterialApp));
      session.progress(
        const ReadingProgress(
          comic: Comic(id: '1', title: 'One'),
          chapterId: '1',
          page: 2,
        ),
      );
      await session.savedProgress;
      await tester.pumpAndSettle();
      final after = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        identical(before, after),
        true,
        reason:
            'Per-page reading progress must not reconstruct application themes',
      );
      await session.setAppearance('color', 0xff476cbb);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .theme!
            .colorScheme
            .primary,
        isNot(before.theme!.colorScheme.primary),
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
