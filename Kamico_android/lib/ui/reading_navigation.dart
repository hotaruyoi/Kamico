import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'app.dart';
import 'reader.dart';
import 'account.dart' show notice;

/// Every reading entry point resolves the same usable offline chapter first.
Future<void> openChapter(
  BuildContext context,
  AppSession session,
  Comic comic,
  Chapter chapter, {
  List<Chapter>? chapters,
  bool fromStart = false,
  bool locked = false,
  bool replace = false,
  bool checkAccess = false,
  bool returnToComic = false,
  VoidCallback? onOpening,
}) async {
  session = session.forSource(comic.source);
  try {
    final local = (await session.downloads.list())
        .where(
          (entry) =>
              entry.comic.key == comic.key && entry.chapter.id == chapter.id,
        )
        .firstOrNull;
    if (!context.mounted) return;
    if (local == null && comic.id.startsWith('local_')) {
      notice(context, '本地文件已移除，请重新导入');
      return;
    }
    if (local == null && locked) {
      notice(context, '本章需要购买后阅读；已下载章节仍可离线打开');
      return;
    }
    if (local == null && checkAccess) {
      final detail = await session.api.detail(comic.id);
      if (!context.mounted) return;
      if (detail.price > 0 && !detail.purchased) {
        notice(context, '本章需要购买后阅读，请返回作品详情确认');
        return;
      }
      chapters ??= detail.chapters;
    }
    final saved = fromStart
        ? null
        : session.store.chapterProgress(comic.key, chapter.id);
    final route = MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(
        session: session,
        comic: comic,
        chapter:
            local?.chapter ??
            chapters?.where((item) => item.id == chapter.id).firstOrNull ??
            chapter,
        chapters: chapters,
        offline: local,
        initialPage: saved?.page ?? 0,
        initialFraction: saved?.fraction ?? 0,
        returnToComic: returnToComic,
      ),
    );
    if (replace) {
      onOpening?.call();
      Navigator.of(context).pushReplacement(route);
    } else {
      await Navigator.of(context).push(route);
    }
  } catch (error) {
    if (context.mounted) notice(context, error);
  }
}
