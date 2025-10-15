import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

extension StringExtension on String {
  String capitalize() => isEmpty ? this : "${this[0].toUpperCase()}${substring(1)}";
}

class EditableCell extends StatefulWidget {
  final String initial;
  final Future<void> Function(String newValue) onSave;
  final TextInputType? keyboardType;
  final bool capitalize;

  final bool numbersOnly;
  final bool allowDecimal;
  final bool allowNegative;

  final String placeholder;

  const EditableCell({
    super.key,
    required this.initial,
    required this.onSave,
    this.keyboardType,
    this.capitalize = false,
    this.numbersOnly = false,
    this.allowDecimal = false,
    this.allowNegative = false,
    this.placeholder = '',
  });

  @override
  State<EditableCell> createState() => EditableCellState();
}

class EditableCellState extends State<EditableCell> {
  late String _value;
  bool _editing = false;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
    _controller.text = _value;
    _focus.addListener(() async {
      if (!_focus.hasFocus && _editing) await _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void beginEdit() {
    setState(() {
      _editing = true;
      _controller.text = _value;
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    });
  }

  List<TextInputFormatter>? _formatters() {
    if (!widget.numbersOnly) return null;
    final buf = StringBuffer('^');
    if (widget.allowNegative) buf.write(r'-?');
    buf.write(r'\d*');
    if (widget.allowDecimal) buf.write(r'(\.\d*)?');
    buf.write(r'$');
    final reg = RegExp(buf.toString());
    return [
      TextInputFormatter.withFunction((oldV, newV) {
        final t = newV.text;
        if (t.isEmpty) return newV;
        return reg.hasMatch(t) ? newV : oldV;
      }),
    ];
  }

  Future<void> _commit() async {
    final trimmed = _controller.text.trim();
    if (trimmed != _value) {
      try {
        await widget.onSave(trimmed);
        if (mounted) setState(() => _value = trimmed);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
        }
      }
    }
    if (mounted) setState(() => _editing = false);
  }

  void _cancel() {
    _controller.text = _value;
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 80),
        child: Shortcuts(
          shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): ActivateIntent()},
          child: Actions(
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _cancel();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                keyboardType: widget.keyboardType,
                textInputAction: TextInputAction.done,
                inputFormatters: _formatters(),
                onSubmitted: (_) => _commit(),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final display = widget.capitalize ? _value.capitalize() : _value;
    final isEmpty = display.isEmpty;

    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Text(
          isEmpty ? widget.placeholder : display,
          style:
              isEmpty
                  ? Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)
                  : null,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
