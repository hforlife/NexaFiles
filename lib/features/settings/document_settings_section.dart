import 'package:flutter/material.dart';
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
  Widget build(BuildContext context) => Column(children: [
        const ListTile(
            leading: Icon(Icons.picture_as_pdf_outlined),
            title: Text('PDF'),
            subtitle: Text(
                'Défilement continu et page unique disponibles dans le lecteur')),
        ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('EPUB'),
            subtitle: Text('Taille ${epubSize.round()} • thème $epubTheme'),
            trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  setState(() => epubTheme = v);
                  _set('epub.theme', v);
                },
                itemBuilder: (_) => const [
                      PopupMenuItem(value: 'light', child: Text('Clair')),
                      PopupMenuItem(value: 'dark', child: Text('Sombre')),
                      PopupMenuItem(value: 'sepia', child: Text('Sépia'))
                    ])),
        ListTile(
            leading: const Icon(Icons.text_snippet_outlined),
            title: const Text('Texte'),
            subtitle: Text('Taille par défaut ${textSize.round()}'),
            trailing: IconButton(
                onPressed: () {
                  setState(() => textSize = textSize >= 21 ? 15 : textSize + 2);
                  _set('text.fontSize', textSize);
                },
                icon: const Icon(Icons.text_increase)))
      ]);
}
