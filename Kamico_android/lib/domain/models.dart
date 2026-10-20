import 'content_source.dart';
export 'content_source.dart';

typedef Json = Map<String, dynamic>;

List<String> strings(dynamic value) => switch (value) {
  List values => values.map((e) => '$e').toList(),
  String text when text.isNotEmpty => [text],
  _ => [],
};

int integer(dynamic value, [int fallback = 0]) =>
    int.tryParse('$value') ?? fallback;

/// Keep upstream abbreviations (e.g. 1.2K); a missing metric is not zero.
String? countLabel(dynamic value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return RegExp(r'^\d[\d.,\s]*(?:[kKmMbB千万亿萬億])?$').hasMatch(text)
      ? text
      : null;
}

class Comic {
  const Comic({
    required this.id,
    required this.title,
    this.authors = const [],
    this.tags = const [],
    this.source = ContentSource.jm,
    this.cover = '',
  });
  final String id;
  final String title;
  final List<String> authors;
  final List<String> tags;
  final ContentSource source;
  final String cover;
  String get key => source.key(id);
  String coverUrl(String imageHost) => cover.isNotEmpty
      ? cover
      : source == ContentSource.pic
      ? ''
      : '$imageHost/media/albums/${id}_3x4.jpg';
  factory Comic.fromJson(Json json) => Comic(
    id: '${json['id'] ?? ''}',
    title: '${json['name'] ?? ''}',
    authors: strings(json['author']),
    tags: strings(json['tags']),
    source: ContentSource.parse(json['source']),
    cover: '${json['cover'] ?? ''}',
  );
  Json toJson() => {
    'id': id,
    'name': title,
    'author': authors,
    'tags': tags,
    'source': source.id,
    if (cover.isNotEmpty) 'cover': cover,
  };
}

class Chapter {
  const Chapter({required this.id, required this.title});
  final String id;
  final String title;
  String get exportId => id.contains('~') ? id.split('~').last : id;
}

class ComicDetail {
  ComicDetail({
    required this.comic,
    required this.description,
    required this.tags,
    required this.favorite,
    required this.chapters,
    this.likes,
  });
  ComicDetail.fromJson(Json json)
    : comic = Comic.fromJson(json),
      description = '${json['description'] ?? ''}',
      tags = strings(json['tags']),
      favorite = json['is_favorite'] == true || '${json['is_favorite']}' == '1',
      likes = countLabel(json['likes']),
      chapters = (json['series'] as List? ?? []).indexed.map((entry) {
        final (index, item) = entry;
        return Chapter(
          id: '${item['id']}',
          title: '${item['name'] ?? ''}'.isEmpty
              ? '第 ${index + 1} 章'
              : '${item['name']}',
        );
      }).toList() {
    works = strings(json['works']);
    actors = strings(json['actors']);
    price = integer(json['price']);
    purchased = json['purchased'] == true || '${json['purchased']}' == '1';
    if (chapters.isEmpty) {
      chapters.add(Chapter(id: comic.id, title: '第 1 章'));
    }
  }
  final Comic comic;
  final String description;
  final List<String> tags;
  List<String> works = [];
  List<String> actors = [];
  int price = 0;
  bool purchased = false;
  final bool favorite;
  final String? likes;
  final List<Chapter> chapters;
}

class HomeSection {
  const HomeSection({
    required this.title,
    required this.type,
    required this.id,
    required this.slug,
    required this.filter,
    required this.items,
  });
  factory HomeSection.fromJson(Json json) => HomeSection(
    title: '${json['title'] ?? ''}',
    type: '${json['type'] ?? ''}',
    id: '${json['id'] ?? ''}',
    slug: '${json['slug'] ?? ''}',
    filter: '${json['filter_val'] ?? ''}',
    items: (json['content'] as List? ?? [])
        .map((e) => Comic.fromJson(e as Json))
        .toList(),
  );
  final String title, type, id, slug, filter;
  final List<Comic> items;
}

class BrowseCategory {
  const BrowseCategory(this.name, this.slug, this.children);
  final String name, slug;
  final List<BrowseCategory> children;
  factory BrowseCategory.fromJson(Json json) => BrowseCategory(
    '${json['name'] ?? ''}',
    '${json['slug'] ?? ''}',
    (json['sub_categories'] as List? ?? [])
        .map((e) => BrowseCategory.fromJson(e as Json))
        .toList(),
  );
}

class CategoryCatalog {
  CategoryCatalog(this.categories, {this.keywords = const {}});
  CategoryCatalog.fromJson(Json json)
    : categories = (json['categories'] as List? ?? [])
          .map((e) => BrowseCategory.fromJson(e as Json))
          .toList(),
      keywords = {
        for (final block in json['blocks'] as List? ?? [])
          '${block['title']}': strings(block['content']),
      };
  final List<BrowseCategory> categories;
  final Map<String, List<String>> keywords;
}

class SearchOptions {
  const SearchOptions({
    this.sort = 'mr',
    this.type = 'site',
    this.year = '',
    this.month = '',
  });
  final String sort, type, year, month;
  Json query(String text, int page) => {
    'search_query': text,
    'page': page,
    'o': sort,
    'search_type': type,
    'lang': 'CN',
    if (year.isNotEmpty) 'y': year,
    if (month.isNotEmpty) 'm': month,
  };
  static String? directId(String input) => RegExp(
    r'^JM(\d+)$',
    caseSensitive: false,
  ).firstMatch(input.trim())?.group(1);
}

class ComicPage {
  const ComicPage(this.items, this.total, {this.more});
  factory ComicPage.fromJson(Json json, {String key = 'content'}) => ComicPage(
    (json[key] as List? ?? []).map((e) => Comic.fromJson(e as Json)).toList(),
    integer(json['total']),
  );
  final List<Comic> items;
  final int total;
  final bool? more;
}

class ReaderPage {
  const ReaderPage({required this.path, required this.name});
  final String path;
  final String name;
}

class ReaderChapter {
  const ReaderChapter({
    required this.id,
    required this.scrambleId,
    required this.pages,
    this.source = ContentSource.jm,
  });
  factory ReaderChapter.fromJson(Json json) {
    final id = '${json['id']}';
    final images = List<Json>.from(json['images'] as List? ?? []);
    images.sort((a, b) => integer(a['page']).compareTo(integer(b['page'])));
    return ReaderChapter(
      id: id,
      scrambleId: integer(json['scramble_id'], -1),
      pages: images.map((entry) {
        final uri = Uri.parse('${entry['image']}');
        final filename = uri.pathSegments.last;
        return ReaderPage(
          path: '/media/photos/$id/$filename',
          name: filename.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        );
      }).toList(),
    );
  }
  final String id;
  final int scrambleId;
  final List<ReaderPage> pages;
  final ContentSource source;
}

class ReadingProgress {
  const ReadingProgress({
    required this.comic,
    required this.chapterId,
    required this.page,
    this.fraction = 0,
  });
  final Comic comic;
  final String chapterId;
  final int page;

  /// Position within a long image, independent of viewport dimensions.
  final double fraction;
  factory ReadingProgress.fromJson(Json json) => ReadingProgress(
    comic: Comic.fromJson(json['comic'] as Json),
    chapterId: '${json['chapterId']}',
    page: integer(json['page']),
    fraction: ((json['fraction'] as num?)?.toDouble() ?? 0).clamp(0, .99),
  );
  Json toJson() => {
    'comic': comic.toJson(),
    'chapterId': chapterId,
    'page': page,
    'fraction': fraction,
  };
}
