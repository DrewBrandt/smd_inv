import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:smd_inv/pages/full_list.dart';


import 'data/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await clearFirestoreCache();
  runApp(MyApp());
}

Future clearFirestoreCache() async {
  try {
    await FirebaseFirestore.instance.clearPersistence();
    print("Firestore cache cleared successfully.");
  } catch (e) {
    print("Failed to clear Firestore cache: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Inventory Viewer',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        visualDensity: VisualDensity.compact,
      ),
      home: FullList(),
    );
  }
}


