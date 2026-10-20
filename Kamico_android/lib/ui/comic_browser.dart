import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'app.dart';
import 'detail_reader.dart';
import 'translations.dart';

class ComicBrowser extends StatefulWidget {
  const ComicBrowser({
    super.key,
    required this.session,
    required this.selected,
    required this.items,
  });
  final AppSession session;
  final Comic selected;
  final List<Comic> items;
  @override
  State<ComicBrowser> createState() => _ComicBrowserState();
}

class _ComicBrowserState extends State<ComicBrowser> {
  late Comic _selected = widget.selected;
  @override
  Widget build(BuildContext context) {
    final items = {
      for (final comic in [widget.selected, ...widget.items]) comic.key: comic,
    }.values.toList();
    return Scaffold(
      appBar: AppBar(title: const AppText('浏览作品')),
      body: LayoutBuilder(
        builder: (context, box) {
          final detail = DetailScreen(
            key: ValueKey(_selected.key),
            session: widget.session.forSource(_selected.source),
            comic: _selected,
            embedded: true,
          );
          if (box.maxWidth < 900) return detail;
          return Row(
            children: [
              SizedBox(
                width: (box.maxWidth * .28).clamp(260, 360),
                child: ListView(
                  key: const PageStorageKey('comic-browser'),
                  children: [
                    for (final comic in items)
                      ListTile(
                        selected: comic.key == _selected.key,
                        title: Text(comic.title),
                        subtitle: Text(comic.authors.join(' / ')),
                        onTap: () => setState(() => _selected = comic),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: detail),
            ],
          );
        },
      ),
    );
  }
}
