import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/database/app_database.dart';
import '../../core/database/models.dart';
import '../../core/readers/pdf_adapter.dart';
import '../../shared/widgets/text_prompt.dart';
import 'reader_kit.dart';

/// PDF reader on pdfrx: continuous scroll, pinch zoom re-rendered sharp,
/// text search with highlights and text selection.
class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({
    super.key,
    required this.session,
    required this.database,
    required this.itemId,
    required this.title,
  });
  final PdfReaderSession session;
  final AppDatabase database;
  final String itemId, title;
  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  static const _background = Color(0xff1c1d21);
  final controller = PdfViewerController();

  /// Created once the viewer is ready: pdfrx 2 reads the controller's
  /// document in the constructor, which throws before the viewer is laid out.
  PdfTextSearcher? searcher;
  late final documentRef = PdfDocumentRefDirect(
    widget.session.document,
    autoDispose: false, // the session owns the document
  );
  final searchInput = TextEditingController();

  /// 0-based, like [PdfLocator]; null until the saved position is restored.
  int? initialPage;
  int page = 0;
  bool controls = true, searching = false;
  ReaderPrefs prefs = const ReaderPrefs();
  Timer? saveTimer;

  int get pageCount => widget.session.pageCount;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    var restored = 0;
    try {
      final saved = await widget.database.progress(widget.itemId);
      final locator = saved == null
          ? null
          : ReadingLocator.decode(saved.locator);
      if (locator is PdfLocator) {
        restored = locator.page.clamp(0, pageCount - 1);
      }
    } catch (_) {}
    prefs = await ReaderPrefs.load();
    unawaited(applyReaderOrientation(prefs.orientation));
    if (mounted) setState(() => initialPage = page = restored);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onReady(PdfDocument document, PdfViewerController controller) {
    if (searcher != null) return;
    // Rebuild so the search button, disabled until now, becomes active.
    setState(() {
      searcher = PdfTextSearcher(controller)..addListener(_refresh);
    });
  }

  void _changed(int value) {
    if (value == page) return;
    setState(() => page = value);
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() => widget.database.saveProgress(
    widget.itemId,
    PdfLocator(page).encode(),
    (page + 1) / pageCount,
  );

  @override
  void dispose() {
    saveTimer?.cancel();
    _save();
    searcher?.removeListener(_refresh);
    searcher?.dispose();
    searchInput.dispose();
    widget.session.dispose();
    releaseReaderOrientation();
    super.dispose();
  }

  void _jump(int value) {
    if (!controller.isReady) return;
    final target = value.clamp(0, pageCount - 1);
    controller.goToPage(pageNumber: target + 1);
    _changed(target);
  }

  void _closeSearch() {
    searcher?.resetTextSearch();
    searchInput.clear();
    setState(() => searching = false);
  }

  Future<void> _addBookmark() async {
    await widget.database.addBookmark(
      widget.itemId,
      PdfLocator(page).encode(),
      label: 'Page ${page + 1}',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Signet ajouté à la page ${page + 1}')),
    );
  }

  Future<void> _bookmarks() async {
    final locator = await showBookmarksSheet(
      context,
      database: widget.database,
      itemId: widget.itemId,
      onAdd: _addBookmark,
    );
    if (locator == null) return;
    final value = ReadingLocator.decode(locator);
    if (value is PdfLocator) _jump(value.page);
  }

  Future<void> _options() => showModalBottomSheet<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Options de lecture',
                style: Theme.of(c).textTheme.titleLarge,
              ),
              const SheetLabel('Orientation de l’écran'),
              OrientationPicker(
                value: prefs.orientation,
                onChanged: (v) {
                  setSheet(() => prefs = prefs.copyWith(orientation: v));
                  applyReaderOrientation(v);
                  prefs.save();
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _askPage() async {
    final value = await showTextPrompt(
      context,
      title: 'Aller à la page',
      initial: '${page + 1}',
      hint: '1 – $pageCount',
      confirm: 'Aller',
      keyboardType: TextInputType.number,
    );
    final number = int.tryParse(value?.trim() ?? '');
    if (number != null) _jump(number - 1);
  }

  Widget _searchBar() {
    final s = searcher;
    final matches = s?.matches.length ?? 0, current = s?.currentIndex;
    return SafeArea(
      bottom: false,
      minimum: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ReaderGlass(
        radius: AppRadius.pill,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: IconTheme(
          data: const IconThemeData(color: ReaderColors.text),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Fermer la recherche',
                onPressed: _closeSearch,
                icon: const Icon(Icons.close_rounded),
              ),
              Expanded(
                child: TextField(
                  controller: searchInput,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(color: ReaderColors.text),
                  cursorColor: ReaderColors.text,
                  decoration: const InputDecoration(
                    hintText: 'Rechercher dans le PDF',
                    hintStyle: TextStyle(color: ReaderColors.muted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) s?.startTextSearch(v.trim());
                  },
                ),
              ),
              if (s?.isSearching ?? false)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ReaderColors.text,
                    ),
                  ),
                )
              else if (searchInput.text.isNotEmpty)
                Text(
                  matches == 0 ? 'Aucun' : '${(current ?? 0) + 1}/$matches',
                  style: const TextStyle(color: ReaderColors.muted),
                ),
              IconButton(
                tooltip: 'Résultat précédent',
                onPressed: matches > 0 ? s!.goToPrevMatch : null,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
              IconButton(
                tooltip: 'Résultat suivant',
                onPressed: matches > 0 ? s!.goToNextMatch : null,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() => ReaderTopBar(
    title: widget.title,
    subtitle: 'PDF · $pageCount pages',
    actions: [
      IconButton(
        tooltip: 'Rechercher',
        onPressed: searcher == null
            ? null
            : () => setState(() => searching = true),
        icon: const Icon(Icons.search_rounded),
      ),
      IconButton(
        tooltip: 'Signets',
        onPressed: _bookmarks,
        icon: const Icon(Icons.bookmarks_outlined),
      ),
      IconButton(
        tooltip: 'Options de lecture',
        onPressed: _options,
        icon: const Icon(Icons.tune_rounded),
      ),
    ],
  );

  Widget _bottomBar() => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: ReaderGlass(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Page précédente',
            onPressed: page > 0 ? () => _jump(page - 1) : null,
            color: ReaderColors.text,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Slider(
              value: page.toDouble(),
              max: (pageCount - 1).clamp(1, pageCount).toDouble(),
              onChanged: pageCount > 1 ? (v) => _jump(v.round()) : null,
            ),
          ),
          IconButton(
            tooltip: 'Page suivante',
            onPressed: page + 1 < pageCount ? () => _jump(page + 1) : null,
            color: ReaderColors.text,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          ReaderPageChip(label: '${page + 1} / $pageCount', onTap: _askPage),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final start = initialPage;
    return Scaffold(
      backgroundColor: _background,
      body: start == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: PdfViewer(
                    documentRef,
                    controller: controller,
                    initialPageNumber: start + 1,
                    params: PdfViewerParams(
                      backgroundColor: _background,
                      margin: 10,
                      maxScale: 8,
                      onViewerReady: _onReady,
                      pagePaintCallbacks: [
                        (canvas, rect, page) => searcher
                            ?.pageTextMatchPaintCallback(canvas, rect, page),
                      ],
                      onPageChanged: (number) {
                        if (number != null) _changed(number - 1);
                      },
                      onGeneralTap: (context, controller, details) {
                        if (details.type != PdfViewerGeneralTapType.tap) {
                          return false;
                        }
                        setState(() => controls = !controls);
                        return true;
                      },
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: searching
                      ? _searchBar()
                      : ReaderFade(visible: controls, child: _topBar()),
                ),
                if (!searching)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ReaderFade(visible: controls, child: _bottomBar()),
                  ),
              ],
            ),
    );
  }
}
