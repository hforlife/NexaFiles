import 'package:flutter/material.dart';
import '../../core/storage/storage_entry.dart';
import '../../core/storage/storage_repository.dart';
import 'files_controller.dart';

class DestinationPicker extends StatefulWidget {
  const DestinationPicker(
      {super.key, required this.storage, required this.roots});
  final StorageRepository storage;
  final List<RootLocation> roots;
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
      if (mounted)
        setState(() => directories =
            values.where((e) => e.kind == StorageEntryKind.directory).toList());
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
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          leading:
              path.isEmpty ? const CloseButton() : BackButton(onPressed: back),
          title: Text(
              path.isEmpty ? 'Choisir une destination' : path.last.displayName),
          actions: [
            if (path.isNotEmpty)
              TextButton(
                  onPressed: () => Navigator.pop(context, path.last.uri),
                  child: const Text('Choisir'))
          ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: path.isEmpty
                  ? [
                      for (final root in widget.roots
                          .where((r) => r.available && r.entry != null))
                        ListTile(
                            leading: const Icon(Icons.folder),
                            title: Text(root.name),
                            onTap: () => open(root.entry!))
                    ]
                  : [
                      for (final folder in directories)
                        ListTile(
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(folder.displayName),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => open(folder))
                    ]));
}
