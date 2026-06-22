import 'package:flutter/material.dart';

class PaletteAction {
  const PaletteAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.actions});
  final List<PaletteAction> actions;

  static Future<void> show(
    BuildContext context, {
    required List<PaletteAction> actions,
  }) {
    return showDialog(
      context: context,
      builder: (_) => CommandPalette(actions: actions),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  String _filter = '';

  List<PaletteAction> get _filtered {
    if (_filter.isEmpty) return widget.actions;
    final q = _filter.toLowerCase();
    return widget.actions
        .where((a) => a.label.toLowerCase().contains(q))
        .toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = _filtered;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Type a command...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: actions.length,
              itemBuilder: (ctx, i) {
                final a = actions[i];
                return ListTile(
                  leading: Icon(a.icon),
                  title: Text(a.label),
                  onTap: () {
                    Navigator.pop(context);
                    a.onTap();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
