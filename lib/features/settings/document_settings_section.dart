import 'package:flutter/material.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/widgets/nexa_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DocumentSettingsSection extends StatefulWidget {
  const DocumentSettingsSection({super.key});
  @override
  State<DocumentSettingsSection> createState() =>
      _DocumentSettingsSectionState();
}

class _DocumentSettingsSectionState extends State<DocumentSettingsSection> {
  double epubSize = 18, textSize = 17;
  String epubTheme = 'light';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        epubSize = p.getDouble('epub.fontSize') ?? 18;
        textSize = p.getDouble('text.fontSize') ?? 17;
        epubTheme = p.getString('epub.theme') ?? 'light';
      });
    }
  }

  Future<void> _set(String key, Object value) async {
    final p = await SharedPreferences.getInstance();
    if (value is double) await p.setDouble(key, value);
    if (value is String) await p.setString(key, value);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const ListTile(
        leading: IconBubble(
          icon: Icons.picture_as_pdf_rounded,
          color: AppColors.pdf,
          size: 42,
        ),
        title: Text('PDF'),
        subtitle: Text('Défilement continu, recherche et signets'),
      ),
      ListTile(
        leading: const IconBubble(
          icon: Icons.menu_book_rounded,
          color: AppColors.reading,
          size: 42,
        ),
        title: const Text('EPUB'),
        subtitle: Text(
          'Taille ${epubSize.round()} · thème ${switch (epubTheme) {
            'dark' => 'sombre',
            'sepia' => 'sépia',
            _ => 'clair',
          }}',
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Thème EPUB',
          icon: const Icon(Icons.palette_outlined),
          onSelected: (v) {
            setState(() => epubTheme = v);
            _set('epub.theme', v);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'light', child: Text('Clair')),
            PopupMenuItem(value: 'dark', child: Text('Sombre')),
            PopupMenuItem(value: 'sepia', child: Text('Sépia')),
          ],
        ),
      ),
      ListTile(
        leading: const IconBubble(
          icon: Icons.text_snippet_rounded,
          color: AppColors.document,
          size: 42,
        ),
        title: const Text('Texte'),
        subtitle: Text('Taille par défaut ${textSize.round()}'),
        trailing: IconButton(
          tooltip: 'Agrandir le texte',
          onPressed: () {
            setState(() => textSize = textSize >= 21 ? 15 : textSize + 2);
            _set('text.fontSize', textSize);
          },
          icon: const Icon(Icons.text_increase),
        ),
      ),
    ],
  );
}
