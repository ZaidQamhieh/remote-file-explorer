import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/hosts/host_list_screen.dart';

void main() {
  runApp(const ProviderScope(child: RemoteFileExplorerApp()));
}

class RemoteFileExplorerApp extends StatelessWidget {
  const RemoteFileExplorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Remote File Explorer',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const HostListScreen(),
    );
  }
}
