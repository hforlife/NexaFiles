import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/router/app_tabs.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/platform/providers.dart';
import '../files/files_controller.dart';
import 'operations_controller.dart';

IconData operationIcon(OperationKind kind) => switch (kind) {
  OperationKind.copy => Icons.copy_rounded,
  OperationKind.move => Icons.drive_file_move_rounded,
  OperationKind.extract => Icons.unarchive_rounded,
  OperationKind.compress => Icons.archive_rounded,
};

/// Compact progress capsule shown above the dock while operations run.
class OperationsBar extends ConsumerWidget {
  const OperationsBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = ref.watch(operationsProvider);
    final running = ops.active;
    if (running.isEmpty) return const SizedBox.shrink();
    final job = running.first, s = context.surfaces;
    final accent = Theme.of(context).colorScheme.primary;
    final p = job.progress;
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 592),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Material(
            color: s.card,
            elevation: 6,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(AppRadius.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => showOperationsSheet(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 36,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: p.fraction,
                            strokeWidth: 3,
                            strokeCap: StrokeCap.round,
                          ),
                          Icon(
                            operationIcon(job.kind),
                            size: 18,
                            color: accent,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            running.length > 1
                                ? '${job.title} · +${running.length - 1}'
                                : job.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            _detail(job),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Annuler',
                      onPressed: () => ops.cancel(job),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _detail(OperationJob job) {
  final p = job.progress;
  return switch (job.state) {
    OperationState.running when job.token.isCancelled => 'Annulation…',
    OperationState.running => [
      if (p.total > 0) '${p.done} / ${p.total}',
      if (p.current != null && p.current!.isNotEmpty) p.current!,
    ].join(' · ').ifEmpty('Préparation…'),
    OperationState.done => 'Terminé',
    OperationState.cancelled => 'Annulé',
    OperationState.failed => job.error ?? 'Échec',
  };
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Every operation of the session, with progress and actions.
Future<void> showOperationsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _OperationsSheet(),
    );

class _OperationsSheet extends ConsumerWidget {
  const _OperationsSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = ref.watch(operationsProvider);
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Opérations',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  if (ops.jobs.any((j) => !j.running))
                    TextButton(
                      onPressed: ops.clearFinished,
                      child: const Text('Effacer les terminées'),
                    ),
                ],
              ),
            ),
            if (ops.jobs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Aucune opération en cours.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: ops.jobs.length,
                  itemBuilder: (_, i) {
                    final job = ops.jobs[i];
                    final color = switch (job.state) {
                      OperationState.failed => theme.colorScheme.error,
                      OperationState.done => AppColors.image,
                      _ => theme.colorScheme.primary,
                    };
                    return ListTile(
                      leading: Icon(
                        job.state == OperationState.done
                            ? Icons.check_circle_rounded
                            : job.state == OperationState.failed
                            ? Icons.error_outline_rounded
                            : operationIcon(job.kind),
                        color: color,
                      ),
                      title: Text(
                        job.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (job.running) ...[
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: job.progress.fraction,
                                minHeight: 5,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          Text(
                            _detail(job),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      trailing: job.running
                          ? IconButton(
                              tooltip: 'Annuler',
                              onPressed: () => ops.cancel(job),
                              icon: const Icon(Icons.close_rounded),
                            )
                          : job.state == OperationState.done &&
                                job.destination != null
                          ? TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                openOperationDestination(ref, job);
                              },
                              child: const Text('Ouvrir'),
                            )
                          : IconButton(
                              tooltip: 'Retirer',
                              onPressed: () => ops.dismiss(job),
                              icon: const Icon(Icons.close_rounded),
                            ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows the folder holding a job's result in the Files tab.
Future<void> openOperationDestination(WidgetRef ref, OperationJob job) async {
  final uri = job.destination;
  if (uri == null) return;
  final entry = await ref.read(storageRepositoryProvider).get(uri);
  if (entry == null) return;
  ref.read(currentTabProvider.notifier).state = AppTab.files;
  await ref.read(filesControllerProvider.notifier).openDirectory(entry);
}

/// Reports finished operations with a snackbar, wherever the user is.
class OperationsListener extends ConsumerStatefulWidget {
  const OperationsListener({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<OperationsListener> createState() => _OperationsListenerState();
}

class _OperationsListenerState extends ConsumerState<OperationsListener> {
  StreamSubscription<OperationJob>? sub;

  @override
  void initState() {
    super.initState();
    sub = ref.read(operationsProvider).finished.listen(_report);
  }

  void _report(OperationJob job) {
    if (!mounted) return;
    final label = operationLabel(job.kind);
    final text = switch (job.state) {
      OperationState.done => '$label terminée',
      OperationState.cancelled => '$label annulée',
      OperationState.failed => '$label impossible : ${job.error ?? 'erreur'}',
      OperationState.running => '',
    };
    // Replace, don't queue: a stale "done" must not hide the next one.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: job.state == OperationState.done && job.destination != null
              ? SnackBarAction(
                  label: 'Ouvrir',
                  onPressed: () => openOperationDestination(ref, job),
                )
              : null,
        ),
      );
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
