import 'package:flutter/material.dart';

import '../explorer_state.dart';

/// App-bar sort menu: tapping a field that's already active flips its
/// ascending/descending direction; tapping a different field switches to it
/// (ascending).
class SortButton extends StatelessWidget {
  const SortButton({super.key, required this.sort, required this.onSort});
  final SortOrder sort;
  final void Function(SortOrder) onSort;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SortField>(
      icon: const Icon(Icons.sort),
      tooltip: 'Sort',
      onSelected: (field) {
        if (sort.field == field) {
          onSort(sort.copyWith(ascending: !sort.ascending));
        } else {
          onSort(SortOrder(field: field));
        }
      },
      itemBuilder: (_) => SortField.values
          .map((f) => PopupMenuItem(
                value: f,
                child: Row(
                  children: [
                    if (sort.field == f)
                      Icon(
                          sort.ascending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 16)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(f.name[0].toUpperCase() + f.name.substring(1)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}
