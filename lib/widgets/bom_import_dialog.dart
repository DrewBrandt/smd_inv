import 'package:flutter/material.dart';
import 'bom_import_widget.dart';

/// Legacy dialog entrypoint kept for compatibility.
/// Internally delegates to the unified BomImportWidget flow.
class BomImportDialog extends StatelessWidget {
  const BomImportDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.85,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: BomImportWidget(
            onCancel: () => Navigator.pop(context),
            onImport: (lines) => Navigator.pop(context, lines),
          ),
        ),
      ),
    );
  }
}
