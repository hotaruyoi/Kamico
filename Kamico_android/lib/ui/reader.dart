import 'reader_settings.dart';
import 'motion.dart';
import 'design_system.dart';
import 'translations.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'dialogs.dart';
import 'failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../domain/models.dart';
import '../domain/reader_options.dart';
import '../data/download_repository.dart';
import '../data/image_size.dart';
import '../data/platform_files.dart';
import 'app.dart';
import 'reading_navigation.dart';
import 'discovery.dart' show openComic;

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.session,
    required this.comic,
    required this.chapter,
    this.initialPage = 0,
    this.initialFraction = 0,
    this.offline,
    this.chapters,
    this.returnToComic = false,
  });
  final AppSession session;
  final Comic comic;
  final Chapter chapter;
  final int initialPage;
  final double initialFraction;
  final OfflineChapter? offline;
  final List<Chapter>? chapters;
  final bool returnToComic;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late Future<ReaderChapter> _chapter;
  ReaderChapter? _data;
  PageController? _pages;
  ItemScrollController _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  late ReaderMode _mode;
  int _index = 0, _generation = 0;
  bool _chrome = true, _autoMoving = false;
  bool _leavingChapter = false;
  bool _goingHome = false;
  double? _sliderTarget;
  String _autoStatus = '';
  List<Chapter>? _knownChapters;
  Timer? _timer;
  Timer? _saveTimer;
  double _fraction = 0, _viewportHeight = 1;
  bool _restoring = false;
  final _imageKeys = <int, GlobalKey>{};
  final _offlineAspects = <int, double>{};
  bool _aspectUpdateScheduled = false;
  // Chapter switching by over-pulling the first or last page. `_pull` is the
  // fraction of the threshold drag that is needed; `_pullExtent` keeps the
  // viewport size the fraction was measured against. What is actually drawn
  // lives in `_pullView`, not in `setState`: rebuilding the page area on every
  // frame of a drag is what risks the 1.0.1 vertical jitter regression.
  double _pull = 0, _pullExtent = 1;
  int _pullDirection = 0;
  bool _chapterSwitching = false;
  final _pullView = ValueNotifier<_PullState>(_PullState.none);
  final _zoom = TransformationController();
  late final AnimationController _release;
  double _releaseFrom = 0;
  void _save() => widget.session.progress(
    ReadingProgress(
      comic: widget.comic,
      chapterId: widget.chapter.id,
      page: _index,
      fraction: _fraction,
    ),
  );
  void _decoded(int index) {
    if (!_restoring || index != _index || _mode != ReaderMode.vertical) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_restoring || !_scroll.isAttached) return;
      final render = _imageKeys[index]?.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;
      _scroll.jumpTo(
        index: index,
        alignment: -_fraction * render.size.height / _viewportHeight,
      );
      _restoring = false;
    });
  }

  int get _seconds =>
      widget.session.store.preferences.getInt('reader_seconds') ?? 5;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mode = readerModeFromPreferences(
      widget.session.store.preferences.getString('reader_layout'),
      widget.session.store.preferences.getInt('reader_mode'),
    );
    _positions.itemPositions.addListener(_scrolled);
    widget.session.images.aspectRevision.addListener(_aspectsChanged);
    _release = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    )..addListener(_releaseTick);
    _release.addStatusListener((status) {
      if (status == AnimationStatus.completed) _resetPull();
    });
    _load();
    _knownChapters = widget.chapters;
    if (_knownChapters == null) _resolveChapters();
    _environment();
  }

  Future<void> _resolveChapters() async {
    try {
      final chapters = widget.offline == null
          ? (await widget.session.api.detail(widget.comic.id)).chapters
          : (await widget.session.downloads.list())
                .where((e) => e.comic.key == widget.comic.key)
                .map((e) => e.chapter)
                .toList();
      if (mounted) {
        setState(
          () => _knownChapters = chapters.isEmpty ? [widget.chapter] : chapters,
        );
      }
    } catch (_) {
      /* Chapter picker offers an explicit retry. */
    }
  }

  Future<void> _environment() async {
    try {
      await PlatformFiles.keepAwake(
        widget.session.store.preferences.getBool('reader_awake') ?? false,
      );
      if (!mounted) return;
      final direction =
          widget.session.store.preferences.getString('reader_orientation') ??
          'system';
      await SystemChrome.setPreferredOrientations(switch (direction) {
        'portrait' => [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ],
        'landscape' => [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        _ => [],
      });
      await PlatformFiles.readerSystemBars(_chrome);
    } catch (_) {
      if (mounted) {
        widget.session.logs.record('READER', 'environment_unavailable');
      }
    }
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    unawaited(
      PlatformFiles.readerSystemBars(_chrome).catchError((Object _) {
        if (mounted) {
          widget.session.logs.record('READER', 'system_ui_unavailable');
        }
      }),
    );
  }

  void _back() {
    if (widget.returnToComic) {
      openComic(context, widget.session, widget.comic, replace: true);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _home() {
    setState(() => _goingHome = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.session.returnHome(context);
    });
  }

  void _stopAuto(String reason) {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _autoStatus = reason);
  }

  Future<void> _pageNumber() async {
    _stopAuto('手动定位，自动阅读已停止');
    final value = await prompt(
      context,
      '跳转页码',
      initial: '${_index + 1}',
      numeric: true,
    );
    if (!mounted || value == null) return;
    final page = int.tryParse(value);
    if (page == null || page < 1 || page > (_data?.pages.length ?? 0)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: AppText('请输入范围内的页码')));
      return;
    }
    await _jump(page - 1);
  }

  void _load() {
    final generation = ++_generation;
    final offline = widget.offline;
    if (offline != null) {
      // Local pages are measured from their headers before the first build, so
      // the strip reserves every extent straight away instead of growing pages
      // after their bitmaps decode.
      _offlineAspects.clear();
      final aspects = measurePageAspects([
        for (var i = 0; i < offline.count; i++) offline.page(i).path,
      ]);
      for (var i = 0; i < aspects.length; i++) {
        final aspect = aspects[i];
        if (aspect != null && aspect > 0) _offlineAspects[i] = aspect;
      }
    }
    final future = offline == null
        ? widget.session.api.chapter(widget.chapter.id)
        : Future.value(
            ReaderChapter(
              id: offline.chapter.id,
              scrambleId: 0,
              pages: List.generate(
                offline.count,
                (i) => ReaderPage(path: '', name: '$i'),
              ),
            ),
          );
    _chapter = future.then((data) {
      if (mounted && generation == _generation) {
        _data = data;
        _index = data.pages.isEmpty
            ? 0
            : widget.initialPage.clamp(0, data.pages.length - 1);
        _controllers();
        _fraction = widget.initialFraction.clamp(0, .99);
        _restoring = _mode == ReaderMode.vertical && _fraction > 0;
        if (data.pages.isNotEmpty && !_restoring) _changed(_index);
      }
      return data;
    });
  }

  void _controllers() {
    _pages?.dispose();

    _pages = PageController(initialPage: _index);
    _scroll = ItemScrollController();
  }

  void _aspectsChanged() {
    if (!mounted || _mode != ReaderMode.vertical || _aspectUpdateScheduled) {
      return;
    }
    void update() {
      _aspectUpdateScheduled = false;
      if (mounted) setState(() {});
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      update();
    } else {
      _aspectUpdateScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => update());
    }
  }

  /// Average page extent used until an online page's own header arrives.
  /// Offline pages are measured up front; unmeasurable ones keep their
  /// intrinsic height rather than an average that could clip them.
  double _fallbackAspect(ReaderChapter data) =>
      widget.session.images.averageAspect(data);

  double? _pageAspect(ReaderChapter data, int index, double fallback) {
    if (widget.offline != null) return _offlineAspects[index];
    final images = widget.session.images;
    final exact = images.aspectFor(data, index);
    if (exact != null) return exact;
    return images.measured(data, index) ? null : fallback;
  }

  void _scrolled() {
    if (!_mode.scrolling || !mounted || _restoring || _leavingChapter) return;
    final visible =
        _positions.itemPositions.value
            .where((p) => p.itemTrailingEdge > .01 && p.itemLeadingEdge < .99)
            .map((p) => p.index)
            .toList()
          ..sort();
    if (visible.isNotEmpty) {
      final position = _positions.itemPositions.value.firstWhere(
        (p) => p.index == visible.first,
      );
      final fraction = _mode == ReaderMode.vertical
          ? (-position.itemLeadingEdge /
                    (position.itemTrailingEdge - position.itemLeadingEdge))
                .clamp(0.0, .99)
          : 0.0;
      if (visible.first != _index) _changed(visible.first);
      _fraction = fraction;
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 250), _save);
    }
  }

  void _changed(int index) {
    if (!mounted) return;
    setState(() => _index = index);
    _resetPull();
    _fraction = 0;
    _save();
    if (widget.offline == null && _data != null) {
      widget.session.images.prefetch(
        _data!,
        index,
        radius:
            (widget.session.store.preferences.getInt('reader_prefetch') ?? 2)
                .clamp(0, 3),
      );
    }
  }

  Future<void> _jump(int index, {bool animate = false}) async {
    _restoring = false;
    final data = _data;
    if (data == null || data.pages.isEmpty) return;
    final target = index.clamp(0, data.pages.length - 1);
    if (_mode.scrolling) {
      if (!_scroll.isAttached) return;
      if (animate) {
        await _scroll.scrollTo(
          index: target,
          duration: Duration(seconds: _seconds),
          curve: Curves.linear,
        );
      } else {
        _scroll.jumpTo(index: target);
      }
    } else {
      final page = target;
      if (_pages?.hasClients != true) return;
      if (animate) {
        await _pages!.animateToPage(
          page,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _pages!.jumpToPage(page);
      }
    }
  }

  void _auto() {
    if (_timer != null) {
      _stopAuto('已手动停止自动阅读');
      return;
    }
    setState(() {
      _autoStatus = '自动阅读中 · 每 $_seconds 秒';
      _timer = Timer.periodic(Duration(seconds: _seconds), (_) async {
        if (_autoMoving) return;
        final count = _data?.pages.length ?? 0;
        if (_index + 1 >= count) {
          _stopAuto('已到章末，自动阅读停止');
          return;
        }
        _autoMoving = true;
        try {
          await _jump(_index + 1, animate: true);
        } finally {
          _autoMoving = false;
        }
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      if (_timer != null) _stopAuto('应用离开前台，自动阅读已停止');
      unawaited(PlatformFiles.keepAwake(false).catchError((Object _) {}));
    } else {
      _environment();
    }
  }

  Future<void> _chapterAction({int? relative}) async {
    _stopAuto('切换章节，自动阅读已停止');
    try {
      final chapters =
          _knownChapters ??
          (widget.offline == null
              ? (widget.chapters ??
                    (await widget.session.api.detail(widget.comic.id)).chapters)
              : ((await widget.session.downloads.list())
                        .where((e) => e.comic.key == widget.comic.key)
                        .toList())
                    .map((e) => e.chapter)
                    .toList());
      _knownChapters = chapters;
      if (!mounted) return;
      Chapter? selected;
      if (relative != null) {
        final index =
            chapters.indexWhere((c) => c.id == widget.chapter.id) + relative;
        if (index >= 0 && index < chapters.length) selected = chapters[index];
      } else {
        selected = await showModalBottomSheet<Chapter>(
          context: context,
          sheetAnimationStyle: AppMotion.sheet(context),
          builder: (context) => SafeArea(
            child: ListView(
              children: chapters
                  .map(
                    (chapter) => ListTile(
                      selected: chapter.id == widget.chapter.id,
                      title: Text(chapter.title),
                      onTap: () => Navigator.pop(context, chapter),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      }
      if (selected == null || selected.id == widget.chapter.id || !mounted) {
        return;
      }
      final target = selected;
      if (!_restoring) _save();
      await widget.session.savedProgress;
      if (!mounted) return;
      await openChapter(
        context,
        widget.session,
        widget.comic,
        target,
        chapters: chapters,
        replace: true,
        checkAccess: true,
        returnToComic: widget.returnToComic,
        onOpening: () {
          _leavingChapter = true;
          _saveTimer?.cancel();
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: AppText('$e')));
      }
    }
  }

  Future<void> _settings() async {
    if (_timer != null) _stopAuto('打开设置，自动阅读已停止');
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: AppMotion.sheet(context),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: 640,
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      builder: (context) => ReaderSettingsPanel(
        session: widget.session,
        mode: _mode,
        onEnvironment: _environment,
        onMode: (mode) {
          if (!mounted || _mode == mode) return;
          setState(() {
            _mode = mode;
            _controllers();
          });
        },
      ),
    );
  }

  Widget _image(int index, {bool width = false, bool zoom = true}) {
    if (widget.offline == null) {
      return ReaderImage(
        session: widget.session,
        chapter: _data!,
        index: index,
        fitWidth: width,
        zoom: zoom,
        onDecoded: () => _decoded(index),
      );
    }
    final image = Image.file(
      widget.offline!.page(index),
      width: width ? double.infinity : null,
      fit: width ? BoxFit.fitWidth : BoxFit.contain,
      alignment: width ? Alignment.topCenter : Alignment.center,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, synchronous) {
        if (frame != null) _decoded(index);
        return width && frame == null
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : child;
      },
      errorBuilder: (_, _, _) => const AppText(
        '离线图片缺失，请重新下载章节',
        style: TextStyle(color: Colors.white),
      ),
    );
    final content = width ? image : Center(child: image);
    return zoom
        ? InteractiveViewer(minScale: 1, maxScale: 5, child: content)
        : content;
  }

  bool _chapterAvailable(int relative) {
    final chapters = _knownChapters;
    if (chapters == null) return false;
    final at = chapters.indexWhere((c) => c.id == widget.chapter.id);
    if (at < 0) return false;
    final target = at + relative;
    return target >= 0 && target < chapters.length;
  }

  // Dragging past the first or the last page starts the same gesture in all
  // three modes: the ring fills with the distance the finger has travelled past
  // the threshold, and the chapter switches the moment it is full. The switch
  // does not wait for the finger to lift, so the overlay must never be the only
  // way to reach the next chapter.
  //
  // The page itself follows the finger and the black band fills the space it
  // vacates, so the band is never painted over a page. The page is moved with a
  // Transform, which is paint-only: changing the page extents while a finger is
  // down reproduces the 1.0.1 vertical jitter (docs/BUG_READER_JITTER.md).
  Axis get _pullAxis => _mode.scrolling ? Axis.vertical : Axis.horizontal;

  /// Share of the axis extent the finger must travel to fill the ring. The page
  /// modes use a smaller share: a horizontal flick that covers a whole page is
  /// the natural gesture there, so a half-width threshold would fire on
  /// ordinary page turns.
  double get _pullThreshold => _pullAxis == Axis.horizontal ? .35 : .5;

  /// Axis direction the page travels for a chapter direction. Both page modes
  /// mirror `ReaderMode.reversed`, so "next chapter" slides the page rightwards
  /// in right-to-left paging and leftwards otherwise.
  int get _pageMoveSign => _mode == ReaderMode.reversePages ? 1 : -1;

  bool _readerNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      if (_pull > 0 || _pullDirection != 0) _startRelease();
      return false;
    }
    if (_chapterSwitching || _leavingChapter || _restoring) return false;
    if ((_data?.pages.length ?? 0) == 0) return false;
    // While the strip is zoomed the drag belongs to InteractiveViewer; a pull
    // there would move the page at the zoomed scale.
    if (_mode.scrolling && _zoom.value.getMaxScaleOnAxis() > 1.01) return false;
    final extent = notification.metrics.viewportDimension;
    if (extent <= 0) return false;
    // `overscroll` reports which end of the content the reader is past, which
    // is what decides the chapter: past the end is the next one, past the
    // start the previous one, in all three modes. It cannot be derived from
    // `_index`, because the vertical strip only reports its first visible page
    // and the last page is therefore never `_index`.
    if (notification is OverscrollNotification) {
      // A ballistic overscroll at the end of a fling must not advance on its
      // own; only a finger drives the pull.
      if (notification.dragDetails == null) return false;
      final boundary = notification.overscroll > 0 ? 1 : -1;
      if (_pullDirection == 0) {
        if (!_chapterAvailable(boundary)) return false;
        _pullDirection = boundary;
      } else if (boundary != _pullDirection) {
        return false;
      }
      _release.stop();
      _pullExtent = extent;
      _commitPull(
          _pull + notification.overscroll.abs() / (extent * _pullThreshold));
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      // Dragging back inside the content gives the pull back, otherwise the
      // ring would stay at its peak after a single overscroll.
      if (_pullDirection == 0 || _pull <= 0) return false;
      final delta = notification.scrollDelta ?? 0;
      final recede = _pullDirection > 0 ? -delta : delta;
      if (recede <= 0) return false;
      _commitPull(_pull - recede / (extent * _pullThreshold));
      return false;
    }
    return false;
  }

  void _startRelease() {
    _releaseFrom = _pull;
    _release.forward(from: 0);
  }

  void _releaseTick() {
    final left = 1 - Curves.easeOutCubic.transform(_release.value);
    _setPull(_releaseFrom * left);
  }

  void _resetPull() {
    if (_release.isAnimating) _release.stop();
    _pull = 0;
    _pullDirection = 0;
    if (_pullView.value != _PullState.none) _pullView.value = _PullState.none;
  }

  void _setPull(double value) {
    final ratio = value.clamp(0.0, 1.0);
    _pull = ratio;
    final next = ratio <= 0 || _pullDirection == 0
        ? _PullState.none
        : _PullState(
            ratio: ratio,
            direction: _pullDirection,
            extent: _pullExtent,
          );
    if (_pullView.value != next) _pullView.value = next;
  }

  void _commitPull(double pulled) {
    final ratio = pulled.clamp(0.0, 1.0);
    if (ratio >= 1) {
      final direction = _pullDirection;
      _resetPull();
      _chapterSwitching = true;
      setState(() {});
      unawaited(
        _chapterAction(relative: direction).whenComplete(() {
          if (mounted) setState(() => _chapterSwitching = false);
        }),
      );
      return;
    }
    if (ratio <= 0) {
      _resetPull();
      return;
    }
    _setPull(ratio);
  }

  /// Paints one frame of the pull: the vacated band under the page, the page
  /// shifted by the distance the finger has travelled, and the ring and hint
  /// that sit inside the band.
  Widget _chapterPullLayer(_PullState pull, Widget content) {
    final active = pull.active;
    final vertical = _pullAxis == Axis.vertical;
    final distance = active ? pull.ratio * pull.extent * _pullThreshold : 0.0;
    // -1 travels towards the start of the axis (up / left), +1 towards the end
    // (down / right). The band always sits on the side the page just vacated.
    final travel = active ? pull.direction * _pageMoveSign : 0;
    final atEnd = travel < 0;
    final half = distance / 2;
    // Aligns the ring and the hint against the vacated edge, then shifts them
    // towards the middle of the band.
    final anchor = vertical
        ? (atEnd ? Alignment.bottomCenter : Alignment.topCenter)
        : (atEnd ? Alignment.centerRight : Alignment.centerLeft);
    final away = atEnd ? -1.0 : 1.0;
    final ringShift = vertical
        ? Offset(0, away * (half - 22))
        : Offset(away * (half - 22), 0);
    final hintShift = vertical
        ? Offset(0, away * (half + 30))
        : Offset(away * (half + 30), 0);
    final band = Positioned(
      left: vertical ? 0 : (atEnd ? null : 0),
      right: vertical ? 0 : (atEnd ? 0 : null),
      top: vertical ? (atEnd ? null : 0) : 0,
      bottom: vertical ? (atEnd ? 0 : null) : 0,
      width: vertical ? null : distance,
      height: vertical ? distance : null,
      child: Offstage(
        offstage: !active,
        child: const IgnorePointer(
          child: ColoredBox(
            key: ValueKey('chapter-pull-blank'),
            color: Colors.black,
          ),
        ),
      ),
    );
    // The tree shape below never changes while a finger is down. Returning
    // `content` on its own when idle and a Stack once the pull starts would
    // re-create the scroll view's element, which drops the in-flight drag; so
    // every frame keeps the same children and only their geometry moves.
    return Stack(
      fit: StackFit.expand,
      children: [
        band,
        Transform.translate(
          key: const ValueKey('chapter-pull-content'),
          offset: vertical
              ? Offset(0, travel * distance)
              : Offset(travel * distance, 0),
          child: content,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Offstage(
              offstage: !active,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Transform.translate(
                    offset: ringShift,
                    child: Align(
                      alignment: anchor,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(
                          key: const ValueKey('chapter-pull-ring'),
                          value: pull.ratio,
                          strokeWidth: 3,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: hintShift,
                    child: Align(
                      alignment: anchor,
                      child: AppText(
                        key: const ValueKey('chapter-pull-label'),
                        pull.direction > 0 ? '继续阅读下一章' : '继续阅读上一章',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .9),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _continuous(BoxConstraints box, ReaderChapter data) {
    _viewportHeight = box.maxHeight;
    final vertical = _mode == ReaderMode.vertical;
    final fallback = vertical ? _fallbackAspect(data) : 1.0;
    final list = ScrollablePositionedList.builder(
      key: ValueKey(_mode),
      padding: EdgeInsets.zero,
      itemScrollController: _scroll,
      itemPositionsListener: _positions,
      initialScrollIndex: _index,
      reverse: _mode.reversed,
      scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
      itemCount: data.pages.length,
      itemBuilder: (_, index) {
        if (!vertical) {
          return SizedBox(
            width: box.maxWidth,
            height: box.maxHeight,
            child: _image(index),
          );
        }
        // Reserve the final extent before the bitmap decodes. A page that grows
        // while it sits above the viewport would otherwise push the content
        // under the reader's finger (the vertical-scroll jitter regression).
        // Do not replace this with the image's intrinsic height when the aspect
        // is known. Unmeasurable pages get no height at all: showing them is
        // better than cropping them to a guessed extent.
        final aspect = _pageAspect(data, index, fallback);
        return SizedBox(
          key: _imageKeys.putIfAbsent(index, () => GlobalKey()),
          width: box.maxWidth,
          height: aspect == null ? null : box.maxWidth * aspect,
          // Keep the child structure stable when the exact aspect arrives;
          // clipping is a no-op once the reserved height matches the page.
          child: ClipRect(child: _image(index, width: true, zoom: false)),
        );
      },
    );
    // One transform keeps neighboring pages joined while zooming the vertical
    // strip. The controller lets the pull gesture step aside while zoomed.
    return vertical
        ? InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            transformationController: _zoom,
            child: list,
          )
        : list;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positions.itemPositions.removeListener(_scrolled);
    widget.session.images.aspectRevision.removeListener(_aspectsChanged);
    _timer?.cancel();
    _saveTimer?.cancel();
    _release.dispose();
    _pullView.dispose();
    _zoom.dispose();
    if (_data?.pages.isNotEmpty == true && !_restoring && !_leavingChapter) {
      _save();
    }
    _pages?.dispose();
    unawaited(PlatformFiles.keepAwake(false).catchError((Object _) {}));
    unawaited(SystemChrome.setPreferredOrientations([]));
    unawaited(PlatformFiles.readerSystemBars(true).catchError((Object _) {}));
    super.dispose();
  }

  Widget _frame(BuildContext context, Widget content, {Widget? controls}) =>
      Stack(
        fit: StackFit.expand,
        children: [
          // `content` is passed as the builder's child so a drag only repaints
          // the page area instead of rebuilding the scrollable under the finger.
          ValueListenableBuilder<_PullState>(
            valueListenable: _pullView,
            child: content,
            builder: (_, pull, child) => _chapterPullLayer(pull, child!),
          ),
          if (_chrome)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SizedBox(
                height: 64 + MediaQuery.viewPaddingOf(context).top,
                child: AppBar(
                  leading: IconButton(
                    tooltip: AppTranslations.text(context, '返回'),
                    onPressed: _back,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  titleSpacing: 0,
                  title: Row(
                    children: [
                      IconButton(
                        tooltip: AppTranslations.text(context, '返回首页'),
                        onPressed: _home,
                        icon: const Icon(Icons.home_outlined),
                      ),
                      Expanded(
                        child: Text(
                          widget.chapter.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: AppTranslations.text(context, '章节列表'),
                      onPressed: () => _chapterAction(),
                      icon: const Icon(Icons.list),
                    ),
                    IconButton(
                      tooltip: AppTranslations.text(context, '阅读设置'),
                      onPressed: _settings,
                      icon: const Icon(Icons.tune),
                    ),
                  ],
                ),
              ),
            ),
          if (controls != null)
            Positioned(left: 0, right: 0, bottom: 0, child: controls),
        ],
      );

  Widget _controls(BuildContext context, ReaderChapter data) => Material(
    color: Colors.black.withValues(alpha: .88),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_chrome && _autoStatus.isNotEmpty)
          Semantics(liveRegion: true, child: AppText(_autoStatus)),
        if (_chrome && _index + 1 >= data.pages.length)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const AppText('本章最后一页'),
              if (_knownChapters == null)
                TextButton(
                  onPressed: () => _chapterAction(),
                  child: const AppText('查看章节'),
                )
              else if (_knownChapters!.indexWhere(
                        (c) => c.id == widget.chapter.id,
                      ) +
                      1 <
                  _knownChapters!.length)
                TextButton.icon(
                  onPressed: () => _chapterAction(relative: 1),
                  icon: const Icon(Icons.skip_next),
                  label: const AppText('继续下一章'),
                )
              else
                const AppText(' · 已到最后一章'),
            ],
          ),
        ListenableBuilder(
          listenable: widget.session,
          builder: (_, _) => widget.session.storageError == null
              ? const SizedBox.shrink()
              : AppText(
                  widget.session.storageError!,
                  style: const TextStyle(color: Colors.orange),
                ),
        ),
        if (_chrome)
          SafeArea(
            top: false,
            child: Row(
              children: [
                IconButton(
                  tooltip: AppTranslations.text(context, '上一页'),
                  color: Colors.white,
                  onPressed: _index == 0 ? null : () => _jump(_index - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Slider(
                    value: _sliderTarget ?? _index.toDouble(),
                    label: '第 ${(_sliderTarget ?? _index).round() + 1} 页',
                    min: 0,
                    max: (data.pages.length - 1).clamp(1, 1000000).toDouble(),
                    onChanged: data.pages.length < 2
                        ? null
                        : (v) => setState(() => _sliderTarget = v),
                    onChangeStart: (_) => _stopAuto('手动定位，自动阅读已停止'),
                    onChangeEnd: (v) {
                      _jump(v.round());
                      setState(() => _sliderTarget = null);
                    },
                  ),
                ),
                TextButton(
                  onPressed: _pageNumber,
                  child: AppText(
                    '${_index + 1}/${data.pages.length}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                IconButton(
                  tooltip: AppTranslations.text(context, '下一页'),
                  color: Colors.white,
                  onPressed: _index + 1 >= data.pages.length
                      ? null
                      : () => _jump(_index + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  tooltip: AppTranslations.text(
                    context,
                    _timer == null ? '自动翻页' : '停止自动翻页',
                  ),
                  color: Colors.white,
                  onPressed: _auto,
                  icon: Icon(_timer == null ? Icons.play_arrow : Icons.pause),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Theme(
    data:
        AppDesign.theme(
          Theme.of(context).colorScheme.primary,
          Brightness.dark,
          Theme.of(context).textTheme.bodyMedium?.fontFamily ?? 'sans-serif',
        ).copyWith(
          textTheme: Theme.of(context).textTheme.apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
        ),
    child: PopScope<void>(
      canPop: !widget.returnToComic || _goingHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: false,
          body: FutureBuilder<ReaderChapter>(
            future: _chapter,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _frame(
                  context,
                  AppFailure(
                    error: snapshot.error!,
                    retry: () => setState(_load),
                    session: widget.session,
                  ),
                );
              }
              final data = snapshot.data;
              if (data == null) {
                return _frame(
                  context,
                  const Center(child: CircularProgressIndicator()),
                );
              }
              if (data.pages.isEmpty) {
                return _frame(
                  context,
                  const Center(
                    child: AppText(
                      '该章节暂无图片',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                );
              }
              return _frame(
                context,
                LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                    key: const ValueKey('reader-tap-surface'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (event) {
                      final center = Rect.fromCenter(
                        center: Offset(box.maxWidth / 2, box.maxHeight / 2),
                        width: box.maxWidth * math.sqrt(.5),
                        height: box.maxHeight * math.sqrt(.5),
                      );
                      if (center.contains(event.localPosition)) _toggleChrome();
                    },
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _readerNotification,
                      child: _mode.scrolling
                          ? _continuous(box, data)
                          : PageView.builder(
                              key: ValueKey(_mode),
                              controller: _pages,
                              reverse: _mode.reversed,
                              itemCount: data.pages.length,
                              onPageChanged: _changed,
                              itemBuilder: (_, page) => _image(page),
                            ),
                    ),
                  ),
                ),
                controls: ListenableBuilder(
                  listenable: widget.session,
                  builder: (_, _) =>
                      _chrome || widget.session.storageError != null
                      ? _controls(context, data)
                      : const SizedBox.shrink(),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// One frame of an in-progress chapter pull. Immutable so the page area can
/// skip rebuilding while only the overlay changes.
class _PullState {
  const _PullState({this.ratio = 0, this.direction = 0, this.extent = 1});

  /// Share of the threshold drag that has been travelled, 0..1.
  final double ratio;

  /// +1 towards the next chapter, -1 towards the previous one, 0 when idle.
  final int direction;

  /// Viewport extent along the reading axis the ratio was measured against.
  final double extent;

  bool get active => ratio > 0 && direction != 0;

  static const none = _PullState();

  @override
  bool operator ==(Object other) =>
      other is _PullState &&
      other.ratio == ratio &&
      other.direction == direction &&
      other.extent == extent;

  @override
  int get hashCode => Object.hash(ratio, direction, extent);
}

class ReaderImage extends StatefulWidget {
  const ReaderImage({
    super.key,
    required this.session,
    required this.chapter,
    required this.index,
    this.fitWidth = false,
    this.zoom = true,
    this.onDecoded,
  });
  final AppSession session;
  final ReaderChapter chapter;
  final int index;
  final bool fitWidth;
  final bool zoom;
  final VoidCallback? onDecoded;
  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  late Future<Uint8List> _image;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _image = widget.session.images.load(widget.chapter, widget.index);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _image,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return SizedBox(
          height: 200,
          child: Center(
            child: TextButton(
              onPressed: () => setState(_load),
              child: const AppText('图片加载失败，点击重试'),
            ),
          ),
        );
      }
      final bytes = snapshot.data;
      if (bytes == null) {
        return const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final image = Image.memory(
        bytes,
        width: widget.fitWidth ? double.infinity : null,
        fit: widget.fitWidth ? BoxFit.fitWidth : BoxFit.contain,
        alignment: widget.fitWidth ? Alignment.topCenter : Alignment.center,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, synchronous) {
          if (frame != null) widget.onDecoded?.call();
          return widget.fitWidth && frame == null
              ? const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                )
              : child;
        },
        errorBuilder: (_, _, _) =>
            const AppText('图片格式不受支持', style: TextStyle(color: Colors.white)),
      );
      final content = widget.fitWidth ? image : Center(child: image);
      return widget.zoom
          ? InteractiveViewer(minScale: 1, maxScale: 5, child: content)
          : content;
    },
  );
}
