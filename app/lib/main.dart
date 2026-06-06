import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/hosts/connection_check_screen.dart';

void main() {
  runApp(const ProviderScope(child: RemoteFileExplorerApp()));
}

class RemoteFileExplorerApp extends StatelessWidget {
  const RemoteFileExplorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Remote File Explorer',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3B6EF6),
        useMaterial3: true,
      ),
      home: const ConnectionCheckScreen(),
    );
  }
}
