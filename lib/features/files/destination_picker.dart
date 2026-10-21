import 'package:flutter/material.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/widgets/nexa_ui.dart';
import '../../core/storage/storage_entry.dart';
import '../../core/storage/storage_repository.dart';
import 'file_rules.dart';
import 'files_controller.dart';

class DestinationPicker extends StatefulWidget {
  const DestinationPicker({
    super.key,
    required this.storage,
    required this.roots,
    this.title = 'Choisir une destination',
  });
  final StorageRepository storage;
  final List<RootLocation> roots;
  final String title;
  @override
  State<DestinationPicker> createState() => _DestinationPickerState();
}

class _DestinationPickerState extends State<DestinationPicker> {
  final path = <StorageEntry>[];
  List<StorageEntry> directories = [];
  bool loading = false;
  Future<void> open(StorageEntry entry) async {
    setState(() {
      loading = true;
      path.add(entry);
    });
    try {
      final values = await widget.storage.list(entry.uri);
      if (mounted) {
        setState(
          () => directories = sortEntries(
            values.where(
              (e) =>
                  e.kind == StorageEntryKind.directory &&
                  !isHiddenFileName(e.displayName),
            ),
            FileSort.name,
            SortDirection.ascending,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> back() async {
    if (path.isEmpty) return;
    if (path.length == 1) {
      setState(() {
        path.clear();
        directories = [];
      });
    } else {
      path.removeLast();
      final current = path.removeLast();
      await open(current);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: path.isEmpty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) back();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: path.isEmpty
            ? const CloseButton()
            : BackButton(onPressed: back),
        title: Text(path.isEmpty ? widget.title : path.last.displayName),
        actions: [
          if (path.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => Navigator.pop(context, path.last.uri),
                child: const Text('Choisir ici'),
              ),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: path.isEmpty
                  ? [
                      for (final root in widget.roots)
                        ListTile(
                          leading: IconBubble(
                            icon: root.removable
                                ? Icons.sd_card_rounded
                                : Icons.smartphone_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 42,
                          ),
                          title: Text(root.name),
                          onTap: () => open(root.entry),
                        ),
                    ]
                  : [
                      for (final folder in directories)
                        ListTile(
                          leading: const IconBubble(
                            icon: Icons.folder_rounded,
                            color: AppColors.folder,
                            size: 42,
                          ),
                          title: Text(folder.displayName),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => open(folder),
                        ),
                    ],
            ),
    ),
  );
}
