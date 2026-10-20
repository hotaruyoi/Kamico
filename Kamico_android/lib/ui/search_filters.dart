import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'discovery.dart' show selectOption, sorts;
import 'design_system.dart';
import 'filled_select.dart';
import 'translations.dart';

const searchTypes = {
  'site': '全部',
  'work': '作品',
  'author': '作者',
  'tag': '标签',
  'character': '角色',
};
const picSorts = {'dd': '最新', 'da': '最早', 'ld': '最多爱心', 'vd': '浏览最多'};
const picCatalogSorts = {
  'mr': '最新',
  'da': '最早',
  'ld': '最多爱心',
  'vd': '浏览最多',
  'mv_t': '日排行',
  'mv_w': '周排行',
  'mv_m': '月排行',
};

/// Draft state is local. Only Apply changes the query or starts a request.
class SearchFilterEditor extends StatefulWidget {
  const SearchFilterEditor({
    super.key,
    required this.initial,
    required this.onApply,
    required this.onCancel,
    this.source = ContentSource.jm,
  });
  final SearchOptions initial;
  final ValueChanged<SearchOptions> onApply;
  final VoidCallback onCancel;
  final ContentSource source;
  @override
  State<SearchFilterEditor> createState() => _SearchFilterEditorState();
}

class _SearchFilterEditorState extends State<SearchFilterEditor> {
  late SearchOptions _draft = widget.initial;
  void _change({String? sort, String? type, String? year, String? month}) =>
      setState(() {
        _draft = SearchOptions(
          sort: sort ?? _draft.sort,
          type: type ?? _draft.type,
          year: year ?? _draft.year,
          month: month ?? _draft.month,
        );
      });
  @override
  Widget build(BuildContext context) => AppPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OptionGrid(
          children: [
            selectOption(
              '排序',
              _draft.sort,
              widget.source == ContentSource.pic
                  ? picSorts
                  : {
                      for (final key in ['mr', 'mv', 'mp', 'tf'])
                        key: sorts[key]!,
                    },
              (v) => _change(sort: v),
            ),
            if (widget.source == ContentSource.jm)
              selectOption(
                '范围',
                _draft.type,
                searchTypes,
                (v) => _change(type: v),
              ),
            if (widget.source == ContentSource.jm)
              selectOption('年份', _draft.year, {
                '': '全部',
                for (var y = DateTime.now().year; y >= 2012; y--) '$y': '$y',
              }, (v) => _change(year: v)),
            if (widget.source == ContentSource.jm)
              selectOption('月份', _draft.month, {
                '': '全部',
                for (var m = 1; m <= 12; m++) '$m': '$m',
              }, (v) => _change(month: v)),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: () => widget.onApply(_draft),
              child: const AppText('应用筛选'),
            ),
            TextButton(
              onPressed: () => setState(
                () => _draft = SearchOptions(
                  sort: widget.source == ContentSource.pic ? 'dd' : 'mr',
                ),
              ),
              child: const AppText('重置筛选'),
            ),
            TextButton(onPressed: widget.onCancel, child: const AppText('取消')),
          ],
        ),
      ],
    ),
  );
}
