import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../constants/firestore_constants.dart';
import '../services/auth_service.dart';
import '../services/board_build_service.dart';
import '../services/inventory_audit_service.dart';

class AdminPage extends StatelessWidget {
  final FirebaseFirestore? firestore;
  final BoardBuildService? buildService;
  final InventoryAuditService? auditService;
  final Future<void> Function(String path, String contents)? writeFile;

  const AdminPage({
    super.key,
    this.firestore,
    this.buildService,
    this.auditService,
    this.writeFile,
  });

  @override
  Widget build(BuildContext context) {
    final db = firestore ?? FirebaseFirestore.instance;
    return _HistoryPanel(
      firestore: db,
      buildService: buildService ?? BoardBuildService(firestore: db),
      auditService: auditService ?? InventoryAuditService(firestore: db),
      writeFile: writeFile ?? _defaultWriteFile,
    );
  }

  static Future<void> _defaultWriteFile(String path, String contents) async {
    final file = File(path);
    await file.writeAsString(contents);
  }
}

class _HistoryPanel extends StatefulWidget {
  final FirebaseFirestore firestore;
  final BoardBuildService buildService;
  final InventoryAuditService auditService;
  final Future<void> Function(String path, String contents) writeFile;

  const _HistoryPanel({
    required this.firestore,
    required this.buildService,
    required this.auditService,
    required this.writeFile,
  });

  @override
  State<_HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<_HistoryPanel> {
  final _undoing = <String>{};
  bool _auditBusy = false;

  bool _ensureCanEdit() {
    if (AuthService.canEdit(AuthService.currentUser)) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You must sign in with a UMD account to edit admin data.',
          ),
        ),
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges(),
      initialData: AuthService.currentUser,
      builder: (context, authSnap) {
        final canEdit = AuthService.canEdit(authSnap.data);
        final cs = Theme.of(context).colorScheme;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.7),
                  ),
                  color: cs.surfaceContainer,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Operations',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Build history, undo operations, and full inventory stock audits.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    if (!canEdit) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'View-only mode. Sign in with a UMD account to run undo or audit replace.',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildAuditCard(canEdit),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream:
                      widget.firestore
                          .collection(FirestoreCollections.history)
                          .orderBy(FirestoreFields.timestamp, descending: true)
                          .limit(300)
                          .snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('Error: ${snap.error}'));
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text('No history entries yet.'),
                      );
                    }

                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder:
                          (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();
                        final action =
                            data[FirestoreFields.action]?.toString() ?? '';
                        final board =
                            data[FirestoreFields.boardName]?.toString() ??
                            '(unknown board)';
                        final qty =
                            (data[FirestoreFields.quantity] as num?)?.toInt() ??
                            0;
                        final ts =
                            data[FirestoreFields.timestamp] as Timestamp?;
                        final undone = data[FirestoreFields.undoneAt] != null;
                        final canUndo = action == 'make_board' && !undone;

                        final consumed =
                            (data[FirestoreFields.consumedItems] as List?) ??
                            const [];
                        final consumedCount = consumed.length;
                        final consumedTotal = consumed.fold<int>(0, (
                          total,
                          entry,
                        ) {
                          final map = Map<String, dynamic>.from(entry as Map);
                          return total +
                              ((map[FirestoreFields.quantity] as num?)
                                      ?.toInt() ??
                                  0);
                        });

                        return Card(
                          child: ListTile(
                            leading: Icon(
                              undone ? Icons.restore : Icons.history,
                              color: undone ? cs.tertiary : cs.primary,
                            ),
                            title: Text('$action - $board'),
                            subtitle: Text(
                              'Qty: $qty | ${_formatTimestamp(ts)} | Items: $consumedCount | Parts consumed: $consumedTotal${undone ? ' | UNDONE' : ''}',
                            ),
                            trailing:
                                canUndo
                                    ? FilledButton.icon(
                                      onPressed:
                                          canEdit && !_undoing.contains(doc.id)
                                              ? () => _undoHistory(doc.id)
                                              : null,
                                      icon:
                                          _undoing.contains(doc.id)
                                              ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                              : const Icon(Icons.undo),
                                      label: const Text('Undo'),
                                    )
                                    : null,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _undoHistory(String historyId) async {
    if (!_ensureCanEdit()) return;

    setState(() => _undoing.add(historyId));
    try {
      await widget.buildService.undoMakeHistory(historyId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Undo complete. Inventory restored.')),
      );
    } on BoardBuildException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Undo failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _undoing.remove(historyId));
      }
    }
  }

  Widget _buildAuditCard(bool canEdit) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Inventory Audit',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Export full inventory to CSV, edit in Excel, then import to replace current stock records.',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _auditBusy || !canEdit ? null : _exportAuditCsv,
                  icon: const Icon(Icons.download),
                  label: const Text('Export CSV'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed:
                      _auditBusy || !canEdit ? null : _importAndReplaceAuditCsv,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.tertiary,
                    foregroundColor: Theme.of(context).colorScheme.onTertiary,
                  ),
                  icon:
                      _auditBusy
                          ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.upload_file),
                  label: const Text('Import & Replace'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportAuditCsv() async {
    if (!_ensureCanEdit()) return;

    setState(() => _auditBusy = true);
    try {
      final csv = await widget.auditService.exportInventoryCsv();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Inventory Audit CSV',
        fileName: 'inventory_audit_export.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (path == null || path.trim().isEmpty) return;
      await widget.writeFile(path, csv);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported inventory audit CSV to $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _auditBusy = false);
    }
  }

  Future<void> _importAndReplaceAuditCsv() async {
    if (!_ensureCanEdit()) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Replace Entire Inventory?'),
            content: const Text(
              'This will DELETE all current inventory items and replace them with rows from the CSV file.\n\nUse only with stock audit files.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('Replace All'),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    setState(() => _auditBusy = true);
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
      );
      if (pick == null || pick.files.isEmpty) return;

      final file = pick.files.first;
      String csvText;
      if (file.bytes != null) {
        csvText = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        csvText = await File(file.path!).readAsString();
      } else {
        throw const AuditReplaceException('Selected file could not be read.');
      }

      final result = await widget.auditService.replaceInventoryFromCsvText(
        csvText,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Replaced inventory: ${result.previousCount} old -> ${result.importedCount} new (${result.skippedRows} skipped rows)',
          ),
        ),
      );
    } on AuditReplaceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _auditBusy = false);
    }
  }

  static String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return 'no timestamp';
    final dt = ts.toDate().toLocal();
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}';
  }
}
