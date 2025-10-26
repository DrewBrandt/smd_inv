// lib/widgets/manual_add_dialog.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ManualAddDialog extends StatefulWidget {
  const ManualAddDialog({super.key});

  @override
  State<ManualAddDialog> createState() => _ManualAddDialogState();
}

class _ManualAddDialogState extends State<ManualAddDialog> {
  final _formKey = GlobalKey<FormState>();
  final _partNumberController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _valueController = TextEditingController();
  final _packageController = TextEditingController();
  final _qtyController = TextEditingController(text: '0');
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  final _vendorLinkController = TextEditingController();
  final _priceController = TextEditingController();
  
  String _selectedType = 'capacitor';
  bool _isSubmitting = false;

  static const _types = [
    'capacitor',
    'resistor',
    'inductor',
    'ic',
    'connector',
    'diode',
    'led',
    'crystal',
    'other',
  ];

  @override
  void dispose() {
    _partNumberController.dispose();
    _descriptionController.dispose();
    _valueController.dispose();
    _packageController.dispose();
    _qtyController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _vendorLinkController.dispose();
    super.dispose();
  }

  bool get _isPassive => ['capacitor', 'resistor', 'inductor'].contains(_selectedType);

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final data = {
        'part_#': _partNumberController.text.trim(),
        'type': _selectedType,
        'value': _isPassive ? _valueController.text.trim() : null,
        'package': _packageController.text.trim(),
        'description': _descriptionController.text.trim(),
        'qty': int.tryParse(_qtyController.text) ?? 0,
        'location': _locationController.text.trim(),
        'notes': _notesController.text.trim(),
        'vendor_link': _vendorLinkController.text.trim(),
        'price_per_unit': _priceController.text.isEmpty ? null : double.tryParse(_priceController.text),
        'datasheet': null,
        'last_updated': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('inventory').add(data);
      
      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Item added successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Inventory Item'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Type dropdown
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Type *',
                    border: OutlineInputBorder(),
                  ),
                  items: _types.map((type) => DropdownMenuItem(
                    value: type,
                    child: Text(type[0].toUpperCase() + type.substring(1)),
                  )).toList(),
                  onChanged: (val) => setState(() => _selectedType = val!),
                ),
                const SizedBox(height: 12),
                
                // Part number
                TextFormField(
                  controller: _partNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Part # *',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., STM32H723VEH6 or CAP-0603-10U',
                  ),
                  validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                
                // Value (only for passives)
                if (_isPassive) ...[
                  TextFormField(
                    controller: _valueController,
                    decoration: const InputDecoration(
                      labelText: 'Value',
                      border: OutlineInputBorder(),
                      hintText: 'e.g., 10k, 2.2u, 100n',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                
                // Package
                TextFormField(
                  controller: _packageController,
                  decoration: const InputDecoration(
                    labelText: 'Package',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., 0603, SOIC-8, QFN-32',
                  ),
                ),
                const SizedBox(height: 12),
                
                // Description
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                    hintText: 'Brief description',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                
                // Quantity
                TextFormField(
                  controller: _qtyController,
                  decoration: const InputDecoration(
                    labelText: 'Quantity *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    if (v?.trim().isEmpty ?? true) return 'Required';
                    if (int.tryParse(v!) == null) return 'Must be a number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                
                // Location
                TextFormField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., Shelf A-3, Drawer 2',
                  ),
                ),
                const SizedBox(height: 12),
                
                // Price per unit
                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(
                    labelText: 'Price Per Unit',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., 0.15',
                    prefixText: '\$ ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                ),
                const SizedBox(height: 12),
                
                // Notes
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                
                // Vendor link
                TextFormField(
                  controller: _vendorLinkController,
                  decoration: const InputDecoration(
                    labelText: 'Vendor Link',
                    border: OutlineInputBorder(),
                    hintText: 'DigiKey/Mouser URL',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add Item'),
        ),
      ],
    );
  }
}