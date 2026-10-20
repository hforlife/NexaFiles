import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/readers/docx_adapter.dart';
import '../../core/storage/storage_repository.dart';

enum DocxTheme { light, dark, sepia }

/// Reads a converted Word document in the sandboxed document WebView
/// (no JavaScript, no network).
class DocxReaderScreen extends StatefulWidget {
  const DocxReaderScreen({
    super.key,
    required this.session,
    required this.storage,
  });
  final DocxReaderSession session;
  final StorageRepository storage;
  @override
  State<DocxReaderScreen> createState() => _DocxReaderScreenState();
}

class _DocxReaderScreenState extends State<DocxReaderScreen> {
  static const _sizeKey = 'docx.fontSize', _themeKey = 'docx.theme';
  double fontSize = 17;
  DocxTheme theme = DocxTheme.light;
  int revision = 0; // recreates the WebView when the style changes

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      fontSize = prefs.getDouble(_sizeKey) ?? 17;
      theme =
          DocxTheme.values.asNameMap()[prefs.getString(_themeKey)] ??
          DocxTheme.light;
      revision++;
    });
  }

  @override
  void dispose() {
    widget.session.dispose();
    super.dispose();
  }

  Future<void> _settings() async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Taille du texte ${fontSize.round()}'),
                Slider(
                  value: fontSize,
                  min: 12,
                  max: 30,
                  onChanged: (v) => setSheet(() => fontSize = v),
                ),
                SegmentedButton<DocxTheme>(
                  segments: const [
                    ButtonSegment(value: DocxTheme.light, label: Text('Clair')),
                    ButtonSegment(value: DocxTheme.dark, label: Text('Sombre')),
                    ButtonSegment(value: DocxTheme.sepia, label: Text('Sépia')),
                  ],
                  selected: {theme},
                  onSelectionChanged: (v) => setSheet(() => theme = v.first),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => revision++);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_sizeKey, fontSize);
    await prefs.setString(_themeKey, theme.name);
  }

  Future<void> _openWith() async {
    try {
      await widget.storage.openExternal(Uri.parse(widget.session.source.id));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune application pour ce fichier.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final background = switch (theme) {
      DocxTheme.light => Colors.white,
      DocxTheme.dark => const Color(0xff171717),
      DocxTheme.sepia => const Color(0xfffff3d6),
    };
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: Text(
          widget.session.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Affichage',
            onPressed: _settings,
            icon: const Icon(Icons.text_fields),
          ),
          IconButton(
            tooltip: 'Ouvrir avec…',
            onPressed: _openWith,
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: SafeArea(
        child: AndroidView(
          key: ValueKey(revision),
          viewType: 'nexa_file/epub',
          creationParams: {
            'root': widget.session.rootPath,
            'path': widget.session.htmlPath,
            'textZoom': (fontSize / 17 * 100).round(),
            'theme': theme.name,
            'lineHeight': 1.5,
            'margin': 20.0,
            'font': 'sans-serif',
          },
          creationParamsCodec: const StandardMessageCodec(),
        ),
      ),
    );
  }
}
