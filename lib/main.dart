import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventory Viewer',
      theme: ThemeData.dark(),
      home: InventoryHome(),
    );
  }
}

class InventoryHome extends StatefulWidget {
  const InventoryHome({super.key});

  @override
  _InventoryHomeState createState() => _InventoryHomeState();
}

class _InventoryHomeState extends State<InventoryHome> {
  String _selectedCollection = 'components';
  final List<String> _collections = [
    'components',
    'ics',
    'misc_parts',
    'boards',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Inventory - $_selectedCollection'),
        actions: [
          DropdownButton<String>(
            value: _selectedCollection,
            dropdownColor: Colors.grey[900],
            icon: Icon(Icons.arrow_drop_down, color: Colors.white),
            onChanged: (value) => setState(() => _selectedCollection = value!),
            items:
                _collections.map((collection) {
                  return DropdownMenuItem(
                    value: collection,
                    child: Text(
                      collection,
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance
                .collection(_selectedCollection)
                .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No data in $_selectedCollection'));
          }

          return ListView(
            children:
                snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return ListTile(
                    title: Text(
                      data['part_type'] ?? data['name'] ?? '[Unnamed]',
                    ),
                    subtitle: Text('Qty: ${data['qty'] ?? '?'}'),
                  );
                }).toList(),
          );
        },
      ),
    );
  }
}
