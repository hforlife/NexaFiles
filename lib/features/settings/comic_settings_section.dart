import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../reader/comic_reader_screen.dart';
import '../../shared/widgets/nexa_ui.dart';

class ComicSettingsSection extends StatefulWidget {
  const ComicSettingsSection({super.key});
  @override
  State<ComicSettingsSection> createState() => _ComicSettingsSectionState();
}

class _ComicSettingsSectionState extends State<ComicSettingsSection> {
  ComicReadingMode mode = ComicReadingMode.single;
  ComicReadingDirection direction = ComicReadingDirection.leftToRight;
  ComicFitMode fit = ComicFitMode.width;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        mode = ComicReadingMode.values.byName(
          p.getString('comic.default.mode') ?? mode.name,
        );
        direction = ComicReadingDirection.values.byName(
          p.getString('comic.default.direction') ?? direction.name,
        );
        fit = ComicFitMode.values.byName(
          p.getString('comic.default.fit') ?? fit.name,
        );
      });
    }
  }

  Future<void> _choose() async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Mode par défaut')),
              RadioGroup<ComicReadingMode>(
                groupValue: mode,
                onChanged: (x) {
                  setState(() => mode = x!);
                  SharedPreferences.getInstance().then(
                    (p) => p.setString('comic.default.mode', x!.name),
                  );
                  Navigator.pop(context);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final v in ComicReadingMode.values)
                      RadioListTile<ComicReadingMode>(
                        value: v,
                        title: Text(switch (v) {
                          ComicReadingMode.single => 'Page unique',
                          ComicReadingMode.vertical => 'Vertical',
                          ComicReadingMode.doublePage => 'Double page',
                        }),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                value: direction == ComicReadingDirection.rightToLeft,
                title: const Text('Droite → gauche'),
                onChanged: (x) {
                  setState(
                    () => direction = x
                        ? ComicReadingDirection.rightToLeft
                        : ComicReadingDirection.leftToRight,
                  );
                  setSheet(() {});
                  SharedPreferences.getInstance().then(
                    (p) =>
                        p.setString('comic.default.direction', direction.name),
                  );
                },
              ),
              const ListTile(title: Text('Ajustement')),
              RadioGroup<ComicFitMode>(
                groupValue: fit,
                onChanged: (x) {
                  setState(() => fit = x!);
                  SharedPreferences.getInstance().then(
                    (p) => p.setString('comic.default.fit', x!.name),
                  );
                  Navigator.pop(context);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final v in ComicFitMode.values)
                      RadioListTile<ComicFitMode>(
                        value: v,
                        title: Text(switch (v) {
                          ComicFitMode.width => 'Largeur',
                          ComicFitMode.height => 'Hauteur',
                          ComicFitMode.free => 'Libre',
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: IconBubble(
      icon: Icons.auto_stories_rounded,
      color: Theme.of(context).colorScheme.primary,
      size: 42,
    ),
    title: const Text('Mangas et BD par défaut'),
    subtitle: Text(
      '${switch (mode) {
        ComicReadingMode.single => 'Page unique',
        ComicReadingMode.vertical => 'Vertical',
        ComicReadingMode.doublePage => 'Double page',
      }} · ${direction == ComicReadingDirection.rightToLeft ? 'Manga (droite → gauche)' : 'Gauche → droite'}',
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: _choose,
  );
}
