import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../core/database/app_database.dart';
import '../../core/database/models.dart';
import '../../core/readers/pdf_adapter.dart';

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
  final controller = PdfViewerController();
  late final searcher = PdfTextSearcher(controller)..addListener(_refresh);
  late final documentRef = PdfDocumentRefDirect(
    widget.session.document,
    autoDispose: false, // the session owns the document
  );
  final searchInput = TextEditingController();

  /// 0-based, like [PdfLocator]; null until the saved position is restored.
  int? initialPage;
  int page = 0;
  bool controls = true, searching = false;
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
    if (mounted) setState(() => initialPage = page = restored);
  }

  void _refresh() {
    if (mounted) setState(() {});
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
    searcher.removeListener(_refresh);
    searcher.dispose();
    searchInput.dispose();
    widget.session.dispose();
    super.dispose();
  }

  void _jump(int value) {
    if (!controller.isReady) return;
    final target = value.clamp(0, pageCount - 1);
    controller.goToPage(pageNumber: target + 1);
    _changed(target);
  }

  void _closeSearch() {
    searcher.resetTextSearch();
    searchInput.clear();
    setState(() => searching = false);
  }

  void _addBookmark() {
    widget.database.addBookmark(
      widget.itemId,
      PdfLocator(page).encode(),
      label: 'Page ${page + 1}',
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Signet ajouté')));
  }

  Future<void> _askPage() async {
    final input = TextEditingController(text: '${page + 1}');
    final value = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Aller à la page'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(helperText: '1 – $pageCount'),
          onSubmitted: (v) => Navigator.pop(c, int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, int.tryParse(input.text)),
            child: const Text('Aller'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value != null) _jump(value - 1);
  }

  PreferredSizeWidget _appBar() {
    if (searching) {
      final matches = searcher.matches.length, current = searcher.currentIndex;
      return AppBar(
        leading: IconButton(
          tooltip: 'Fermer la recherche',
          onPressed: _closeSearch,
          icon: const Icon(Icons.close),
        ),
        title: TextField(
          controller: searchInput,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Rechercher dans le PDF',
            border: InputBorder.none,
            filled: false,
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) searcher.startTextSearch(v.trim());
          },
        ),
        actions: [
          if (searcher.isSearching)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (searchInput.text.isNotEmpty)
            Center(
              child: Text(
                matches == 0 ? 'Aucun' : '${(current ?? 0) + 1}/$matches',
              ),
            ),
          IconButton(
            tooltip: 'Résultat précédent',
            onPressed: matches > 0 ? searcher.goToPrevMatch : null,
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          IconButton(
            tooltip: 'Résultat suivant',
            onPressed: matches > 0 ? searcher.goToNextMatch : null,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
        ],
      );
    }
    return AppBar(
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: 'Rechercher',
          onPressed: () => setState(() => searching = true),
          icon: const Icon(Icons.search),
        ),
        IconButton(
          tooltip: 'Ajouter un signet',
          onPressed: _addBookmark,
          icon: const Icon(Icons.bookmark_add_outlined),
        ),
      ],
    );
  }

  Widget _bottomBar() => SafeArea(
    child: Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Page précédente',
            onPressed: page > 0 ? () => _jump(page - 1) : null,
            color: Colors.white,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Slider(
              value: page.toDouble(),
              max: (pageCount - 1).clamp(1, pageCount).toDouble(),
              onChanged: pageCount > 1 ? (v) => _jump(v.round()) : null,
            ),
          ),
          TextButton(
            onPressed: _askPage,
            child: Text(
              '${page + 1} / $pageCount',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Page suivante',
            onPressed: page + 1 < pageCount ? () => _jump(page + 1) : null,
            color: Colors.white,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final start = initialPage;
    return Scaffold(
      backgroundColor: const Color(0xff202124),
      appBar: controls || searching ? _appBar() : null,
      body: start == null
          ? const Center(child: CircularProgressIndicator())
          : PdfViewer(
              documentRef,
              controller: controller,
              initialPageNumber: start + 1,
              params: PdfViewerParams(
                backgroundColor: const Color(0xff202124),
                maxScale: 8,
                pagePaintCallbacks: [searcher.pageTextMatchPaintCallback],
                onPageChanged: (number) {
                  if (number != null) _changed(number - 1);
                },
                onGeneralTap: (context, controller, details) {
                  if (details.type != PdfViewerGeneralTapType.tap) return false;
                  setState(() => controls = !controls);
                  return true;
                },
                viewerOverlayBuilder: (context, size, handleLinkTap) => [
                  PdfViewerScrollThumb(
                    controller: controller,
                    orientation: ScrollbarOrientation.right,
                    thumbSize: const Size(48, 28),
                    thumbBuilder:
                        (context, thumbSize, pageNumber, controller) =>
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${pageNumber ?? ''}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: controls && !searching ? _bottomBar() : null,
    );
  }
}
