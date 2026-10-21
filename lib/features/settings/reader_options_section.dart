import 'package:flutter/material.dart';
import '../reader/reader_kit.dart';

/// Reading options shared by every reader (also editable while reading).
class ReaderOptionsSection extends StatefulWidget {
  const ReaderOptionsSection({super.key});
  @override
  State<ReaderOptionsSection> createState() => _ReaderOptionsSectionState();
}

class _ReaderOptionsSectionState extends State<ReaderOptionsSection> {
  ReaderPrefs? prefs;

  @override
  void initState() {
    super.initState();
    ReaderPrefs.load().then((v) {
      if (mounted) setState(() => prefs = v);
    });
  }

  void _set(ReaderPrefs value) {
    setState(() => prefs = value);
    value.save();
  }

  @override
  Widget build(BuildContext context) {
    final p = prefs;
    if (p == null) return const SizedBox(height: 120);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetLabel('Zones de changement de page'),
          TapLayoutPicker(
            value: p.tapLayout,
            onChanged: (v) => _set(p.copyWith(tapLayout: v)),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: p.doubleTapZoom,
            title: const Text('Zoom au double tap'),
            subtitle: const Text(
              'Mangas et BD. Ajoute un court délai aux taps simples.',
            ),
            onChanged: (v) => _set(p.copyWith(doubleTapZoom: v)),
          ),
          const SheetLabel('Orientation pendant la lecture'),
          OrientationPicker(
            value: p.orientation,
            onChanged: (v) => _set(p.copyWith(orientation: v)),
          ),
        ],
      ),
    );
  }
}
