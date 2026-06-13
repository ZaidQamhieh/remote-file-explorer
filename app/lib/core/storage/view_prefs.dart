/// Shared view-layer value types: list/grid sort order and entry density.
///
/// These are the vocabulary the explorer and the settings system speak. The
/// persistence and resolution of *which* sort/density/layout applies now lives
/// in the two-tier settings model (`core/settings/`); this file holds only the
/// immutable types so widgets and the resolver can share them without importing
/// the controller.
library;

// ---------------------------------------------------------------------------
// Sort order
// ---------------------------------------------------------------------------

/// Fields the explorer listing can be sorted by. Directories are always
/// listed before files regardless of [SortField] (see
/// `explorer_state._sortEntries`); this enum only controls the comparator
/// used within each group.
enum SortField { name, size, date, type }

/// A sort field plus direction. Immutable; [copyWith] flips/changes either
/// independently.
class SortOrder {
  const SortOrder({this.field = SortField.name, this.ascending = true});

  final SortField field;
  final bool ascending;

  SortOrder copyWith({SortField? field, bool? ascending}) => SortOrder(
        field: field ?? this.field,
        ascending: ascending ?? this.ascending,
      );

  @override
  bool operator ==(Object other) =>
      other is SortOrder &&
      other.field == field &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);
}

// ---------------------------------------------------------------------------
// Density
// ---------------------------------------------------------------------------

/// List-tile density. Comfortable is the default two-line row (~72dp);
/// compact is a single-line row (~52dp) with metadata inline after the name.
/// Grid cell anatomy is unaffected by density (per the design spec).
enum EntryDensity { comfortable, compact }
