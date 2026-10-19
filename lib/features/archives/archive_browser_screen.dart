import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/archives/archive_core.dart';
import '../../core/storage/storage_repository.dart';
import '../files/destination_picker.dart';
import '../files/file_operation_service.dart';
import '../files/files_controller.dart';
import 'archive_extraction_service.dart';

class ArchiveBrowserScreen extends StatefulWidget {
  const ArchiveBrowserScreen(
      {super.key,
      required this.name,
      required this.session,
      required this.storage,
      required this.roots,
      this.defaultDestination});
  final String name;
  final ArchiveSession session;
  final StorageRepository storage;
  final List<RootLocation> roots;
  final Uri? defaultDestination;
  @override
  State<ArchiveBrowserScreen> createState() => _ArchiveBrowserScreenState();
}

class _ArchiveBrowserScreenState extends State<ArchiveBrowserScreen> {
  List<ArchiveEntry>? entries;
  String prefix = '';
  Object? error;
  @override
  void initState() {
    super.initState();
    widget.session.listEntries().then((v) {
      if (mounted) setState(() => entries = v);
    }).catchError((e) {
      if (mounted) setState(() => error = e);
    });
  }

  @override
  void dispose() {
    widget.session.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _children();
    final body = error != null
        ? const Center(
            child: Text(
                'Impossible d’ouvrir cette archive.\nLe fichier semble endommagé ou utilise une méthode non prise en charge.',
                textAlign: TextAlign.center))
        : entries == null
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                SizedBox(
                    height: 48,
                    child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          TextButton.icon(
                              onPressed: prefix.isEmpty ? null : _parent,
                              icon: const Icon(Icons.home_outlined),
                              label: const Text('Archive')),
                          for (final part
                              in prefix.split('/').where((e) => e.isNotEmpty))
                            Row(children: [
                              const Icon(Icons.chevron_right, size: 18),
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(part))
                            ]),
                        ])),
                Expanded(
                    child: ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final item = shown[i];
                          return ListTile(
                            leading: Icon(item.virtualDirectory
                                ? Icons.folder_outlined
                                : Icons.insert_drive_file_outlined),
                            title: Text(item.name),
                            subtitle: item.entry == null
                                ? null
                                : Text(
                                    '${item.entry!.uncompressedSize} octets'),
                            onTap: item.virtualDirectory
                                ? () => setState(() => prefix = prefix.isEmpty
                                    ? item.name
                                    : '$prefix/${item.name}')
                                : () => _entryInfo(item.entry!),
                            trailing: item.entry == null
                                ? null
                                : PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'extract') {
                                        _chooseAndExtract(item.entry);
                                      }
                                      if (v == 'info') _entryInfo(item.entry!);
                                    },
                                    itemBuilder: (_) => const [
                                          PopupMenuItem(
                                              value: 'extract',
                                              child: Text(
                                                  'Extraire cette entrée')),
                                          PopupMenuItem(
                                              value: 'info',
                                              child: Text('Informations'))
                                        ]),
                          );
                        })),
              ]);
    return WillPopScope(
        onWillPop: () async {
          if (prefix.isEmpty) return true;
          _parent();
          return false;
        },
        child: Scaffold(
          appBar: AppBar(title: Text(widget.name), actions: [
            if (widget.defaultDestination != null)
              IconButton(
                  tooltip: 'Extraire ici',
                  onPressed: () => _extract(widget.defaultDestination!),
                  icon: const Icon(Icons.unarchive_outlined)),
            IconButton(
                tooltip: 'Extraire vers…',
                onPressed: _chooseAndExtract,
                icon: const Icon(Icons.drive_file_move_outline))
          ]),
          body: body,
        ));
  }

  void _parent() {
    final parts = prefix.split('/')..removeLast();
    setState(() => prefix = parts.join('/'));
  }

  void _entryInfo(ArchiveEntry entry) => showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
              child: ListView(shrinkWrap: true, children: [
            ListTile(
                title: Text(entry.path),
                subtitle: Text('${entry.uncompressedSize} octets')),
            ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Extraire cette entrée'),
                onTap: () {
                  Navigator.pop(c);
                  _chooseAndExtract(entry);
                })
          ])));
  List<_BrowserItem> _children() {
    if (entries == null) return [];
    final result = <String, _BrowserItem>{};
    final base = prefix.isEmpty ? '' : '$prefix/';
    for (final entry in entries!) {
      if (!entry.path.startsWith(base)) continue;
      final rest = entry.path.substring(base.length);
      if (rest.isEmpty) continue;
      final slash = rest.indexOf('/');
      if (slash >= 0) {
        final name = rest.substring(0, slash);
        result[name] = _BrowserItem(name, true, null);
      } else {
        result[rest] = _BrowserItem(rest, entry.isDirectory, entry);
      }
    }
    final values = result.values.toList()
      ..sort((a, b) {
        if (a.virtualDirectory != b.virtualDirectory) {
          return a.virtualDirectory ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return values;
  }

  Future<void> _chooseAndExtract([ArchiveEntry? only]) async {
    final target = await Navigator.push<Uri>(
        context,
        MaterialPageRoute(
            builder: (_) => DestinationPicker(
                storage: widget.storage, roots: widget.roots)));
    if (target != null) _extract(target, only);
  }

  void _extract(Uri destination, [ArchiveEntry? only]) {
    final token = CancellationToken();
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => _ExtractionDialog(
            stream: ArchiveExtractionService(widget.storage).extract(
                widget.session, destination,
                only: only, cancellation: token),
            cancel: token.cancel,
            done: () {
              Navigator.pop(dialog);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Extraction terminée')));
            }));
  }
}

class _BrowserItem {
  const _BrowserItem(this.name, this.virtualDirectory, this.entry);
  final String name;
  final bool virtualDirectory;
  final ArchiveEntry? entry;
}

class _ExtractionDialog extends StatefulWidget {
  const _ExtractionDialog(
      {required this.stream, required this.cancel, required this.done});
  final Stream<ExtractionProgress> stream;
  final VoidCallback cancel, done;
  @override
  State<_ExtractionDialog> createState() => _ExtractionDialogState();
}

class _ExtractionDialogState extends State<_ExtractionDialog> {
  ExtractionProgress? value;
  Object? error;
  StreamSubscription? sub;
  @override
  void initState() {
    super.initState();
    sub = widget.stream.listen((v) {
      if (v.done) {
        widget.done();
      } else if (mounted) {
        setState(() => value = v);
      }
    }, onError: (e) {
      if (mounted) setState(() => error = e);
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Extraction'),
          content: error != null
              ? const Text(
                  'Impossible d’extraire cette archive. Vérifiez le fichier et l’espace disponible.')
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  LinearProgressIndicator(value: value?.fraction),
                  const SizedBox(height: 12),
                  Text(value?.current ?? 'Préparation…'),
                  if (value != null)
                    Text('${value!.completed} / ${value!.total}')
                ]),
          actions: [
            TextButton(
                onPressed: () {
                  widget.cancel();
                  Navigator.pop(context);
                },
                child: const Text('Annuler'))
          ]);
}
