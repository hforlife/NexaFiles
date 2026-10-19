import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../reader/comic_reader_screen.dart';

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
    if (mounted)
      setState(() {
        mode = ComicReadingMode.values
            .byName(p.getString('comic.default.mode') ?? mode.name);
        direction = ComicReadingDirection.values
            .byName(p.getString('comic.default.direction') ?? direction.name);
        fit = ComicFitMode.values
            .byName(p.getString('comic.default.fit') ?? fit.name);
      });
  }

  Future<void> _choose() async {
    await showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('Mode par défaut')),
              for (final v in ComicReadingMode.values)
                RadioListTile(
                    value: v,
                    groupValue: mode,
                    title: Text(switch (v) {
                      ComicReadingMode.single => 'Page unique',
                      ComicReadingMode.vertical => 'Vertical',
                      ComicReadingMode.doublePage => 'Double page'
                    }),
                    onChanged: (x) {
                      setState(() => mode = x!);
                      SharedPreferences.getInstance().then(
                          (p) => p.setString('comic.default.mode', x!.name));
                      Navigator.pop(context);
                    }),
              SwitchListTile(
                  value: direction == ComicReadingDirection.rightToLeft,
                  title: const Text('Droite → gauche'),
                  onChanged: (x) {
                    setState(() => direction = x
                        ? ComicReadingDirection.rightToLeft
                        : ComicReadingDirection.leftToRight);
                    SharedPreferences.getInstance().then((p) =>
                        p.setString('comic.default.direction', direction.name));
                  }),
              const ListTile(title: Text('Ajustement')),
              for (final v in ComicFitMode.values)
                RadioListTile(
                    value: v,
                    groupValue: fit,
                    title: Text(switch (v) {
                      ComicFitMode.width => 'Largeur',
                      ComicFitMode.height => 'Hauteur',
                      ComicFitMode.free => 'Libre'
                    }),
                    onChanged: (x) {
                      setState(() => fit = x!);
                      SharedPreferences.getInstance().then(
                          (p) => p.setString('comic.default.fit', x!.name));
                      Navigator.pop(context);
                    })
            ])));
  }

  @override
  Widget build(BuildContext context) => ListTile(
      leading: const Icon(Icons.auto_stories_outlined),
      title: const Text('Lecture Manga / BD'),
      subtitle: Text(
          '${mode.name} • ${direction == ComicReadingDirection.rightToLeft ? 'RTL' : 'LTR'} • ${fit.name}'),
      onTap: _choose);
}
