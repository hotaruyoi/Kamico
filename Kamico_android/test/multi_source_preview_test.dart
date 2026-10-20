import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/translations.dart';
import 'multi_source_test.dart' show FixtureJm, FixturePic;
import 'ui_design_test.dart' show capture, captureUi;

void main() {
  setUpAll(() async {
    if (!captureUi) return;
    await AppTranslations.load();
    for (final entry in {
      'Review CJK': 'C:/Windows/Fonts/msyh.ttc',
      'MaterialIcons':
          'D:/Application/Flutter/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(entry.value).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  testWidgets(
    'synthetic Pic account toggle and grouped local shelf previews',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'appearance': jsonEncode({'font': 'Review CJK'}),
      });
      final store = LocalStore(await SharedPreferences.getInstance());
      await store.addLocal(
        const Comic(id: 'sample-jm', title: 'JM 示例作品', authors: ['合成作者']),
      );
      await store.addLocal(
        const Comic(
          id: 'sample-pic',
          title: 'Pic 示例作品',
          source: ContentSource.pic,
          authors: ['合成作者'],
        ),
      );
      final session = AppSession(
        store,
        client: FixtureJm(),
        picClient: FixturePic(),
      );
      addTearDown(session.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: JmApp(session: session),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('content-source-toggle')));
      await tester.pumpAndSettle();
      await capture(tester, key, 'my-pic-source');
      await tester.tap(find.text('书架').last);
      await tester.pumpAndSettle();
      await capture(tester, key, 'local-source-sections');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !captureUi,
  );
}
