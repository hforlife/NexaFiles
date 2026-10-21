import 'package:flutter/material.dart';

/// Asks for one line of text in a dialog; null when cancelled.
///
/// The dialog owns its controller and disposes it once the route is gone:
/// disposing right after `showDialog` returns crashes, because the closing
/// animation still builds the text field.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  String initial = '',
  String? message,
  String? hint,
  String? errorText,
  String confirm = 'Valider',
  IconData? icon,
  bool obscure = false,
  bool selectBaseName = false,
  TextInputType? keyboardType,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextPromptDialog(
    title: title,
    initial: initial,
    message: message,
    hint: hint,
    errorText: errorText,
    confirm: confirm,
    icon: icon,
    obscure: obscure,
    selectBaseName: selectBaseName,
    keyboardType: keyboardType,
  ),
);

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.initial,
    required this.confirm,
    required this.obscure,
    required this.selectBaseName,
    this.message,
    this.hint,
    this.errorText,
    this.icon,
    this.keyboardType,
  });
  final String title, initial, confirm;
  final String? message, hint, errorText;
  final IconData? icon;
  final bool obscure, selectBaseName;
  final TextInputType? keyboardType;
  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final input = TextEditingController(text: widget.initial);
  late bool hidden = widget.obscure;

  @override
  void initState() {
    super.initState();
    // Select the name without its extension, like file managers do.
    final dot = widget.selectBaseName ? widget.initial.lastIndexOf('.') : -1;
    input.selection = TextSelection(
      baseOffset: 0,
      extentOffset: dot > 0 ? dot : widget.initial.length,
    );
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, input.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: widget.icon == null ? null : Icon(widget.icon),
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.message != null) ...[
          Text(widget.message!),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: input,
          autofocus: true,
          obscureText: hidden,
          keyboardType: widget.keyboardType,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: widget.errorText,
            suffixIcon: widget.obscure
                ? IconButton(
                    tooltip: hidden ? 'Afficher' : 'Masquer',
                    onPressed: () => setState(() => hidden = !hidden),
                    icon: Icon(
                      hidden
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                  )
                : null,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.confirm)),
    ],
  );
}
