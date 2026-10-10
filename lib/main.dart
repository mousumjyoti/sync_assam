import 'package:flutter/material.dart';

import 'package:sync_assam/pages/home_page.dart';

void main() {
  runApp(const SyncAssamApp());
}

class SyncAssamApp extends StatelessWidget {
  const SyncAssamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SRT Sync',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
