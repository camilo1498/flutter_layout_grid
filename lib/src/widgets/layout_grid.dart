import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../rendering/layout_grid.dart';
import '../rendering/track_size.dart';
import 'placement.dart';

/// Controls how the auto-placement algorithm works, specifying exactly how
/// auto-placed items get flowed into the grid.
class AutoPlacement {
  /// Items are placed by filling each row in turn, adding new rows as
  /// necessary. If neither row nor column is provided, row is assumed.
  static const rowSparse =
      AutoPlacement._(TrackType.row, AutoPlacementPacking.sparse);

  /// Items are placed by filling each row in turn, attempting to fill in holes
  /// earlier in the grid, if smaller items come up later, adding rows as
  /// necessary. This may cause items to appear out-of-order, when doing so
  /// would fill in holes left by larger items.
  static const rowDense =
      AutoPlacement._(TrackType.row, AutoPlacementPacking.dense);

  /// Items are placed by filling each column in turn, adding new columns as
  /// necessary.
  static const columnSparse =
      AutoPlacement._(TrackType.column, AutoPlacementPacking.sparse);

  /// Items are placed by filling each column in turn, attempting to fill in
  /// holes earlier in the grid, if smaller items come up later, adding columns
  /// as necessary. This may cause items to appear out-of-order, when doing so
  /// would fill in holes left by larger items.
  static const columnDense =
      AutoPlacement._(TrackType.column, AutoPlacementPacking.dense);

  const AutoPlacement._(this.trackType, this.packing);
  final TrackType trackType;
  final AutoPlacementPacking packing;

  @override
  String toString() {
    switch (this) {
      case rowSparse:
        return 'AutoPlacement.rowSparse';
      case rowDense:
        return 'AutoPlacement.rowDense';
      case columnSparse:
        return 'AutoPlacement.columnSparse';
      case columnDense:
        return 'AutoPlacement.columnDense';
    }
    throw StateError('toString() called on unknown AutoPlacement');
  }

  /// The list of all available AutoPlacement values
  static const List<AutoPlacement> values = [
    rowSparse,
    rowDense,
    columnSparse,
    columnDense,
  ];
}

/// Determines the constraints available to the grid layout algorithm.
enum GridFit {
  /// The constraints passed to the grid from its parent are tightened to the
  /// biggest size allowed. For example, if the grid has loose constraints with
  /// a width in the range 10 to 100 and a height in the range 0 to 600, then
  /// the children will be instructed to fill the entire 100×600 size.
  ///
  /// If the constraints passed to the grid are unbounded on a dimension, the
  /// children will be allowed to maximize their sizes on that axis (column
  /// taking preference).
  expand,

  /// The constraints passed to the grid from its parent are loosened. For
  /// example, if the grid has constraints that force it to 350x600, then this
  /// would allow the children of the grid to collectively have a width between
  /// zero and 350 and a height from zero to 600.
  loose,

  /// The constraints passed to the grid from its parent are interpreted as-is.
  passthrough,
}

/// Lays out its children using a approximation of the CSS Grid Layout
/// algorithm, as described here:
///
/// https://drafts.csswg.org/css-grid/
///
/// If a grid item falls outside of the area defined by the template tracks, an
/// [FlutterError] will be thrown during layout.
class LayoutGrid extends StatelessWidget {
  const LayoutGrid({
    super.key,
    this.autoPlacement = AutoPlacement.rowSparse,
    this.gridFit = GridFit.expand,
    this.areas,
    required this.columnSizes,
    required this.rowSizes,
    this.rowGap = 0,
    this.columnGap = 0,
    this.textDirection,
    this.addRepaintBoundaries = false,
    this.children = const [],
  });

  /// Controls how the auto-placement algorithm works, specifying exactly how
  /// auto-placed items get flowed into the grid.
  final AutoPlacement autoPlacement;

  /// Determines the constraints available to the grid layout algorithm.
  final GridFit gridFit;

  /// Defines named areas of the grid for placement of grid items by name.
  final String? areas;

  /// Defines the track sizing functions of the grid's columns.
  final List<TrackSize> columnSizes;

  /// Defines the track sizing functions of the grid's rows.
  final List<TrackSize> rowSizes;

  /// Space between column tracks
  final double columnGap;

  /// Space between row tracks
  final double rowGap;

  /// The text direction used to resolve column ordering.
  final TextDirection? textDirection;

  /// Whether to wrap each child in a [RepaintBoundary].
  ///
  /// This is a convenience property that applies [RepaintBoundary] to all
  /// children of the grid. If a child is already wrapped in a placement widget
  /// ([GridPlacement] or [NamedAreaGridPlacement]), the [RepaintBoundary] will
  /// be placed *inside* the placement widget to maintain [ParentData]
  /// correctness.
  final bool addRepaintBoundaries;

  /// The children of the grid.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final childrenWithBoundaries = addRepaintBoundaries
        ? children.map((child) {
            if (child is GridPlacement) {
              return GridPlacement(
                key: child.key,
                columnStart: child.columnStart,
                columnSpan: child.columnSpan,
                rowStart: child.rowStart,
                rowSpan: child.rowSpan,
                addRepaintBoundary: true,
                child: RepaintBoundary(child: child.child),
              );
            } else if (child is NamedAreaGridPlacement) {
              return NamedAreaGridPlacement(
                key: child.key,
                areaName: child.areaName,
                addRepaintBoundary: true,
                child: RepaintBoundary(child: child.child),
              );
            }
            return RepaintBoundary(child: child);
          }).toList()
        : children;

    return _LayoutGrid(
      autoPlacement: autoPlacement,
      gridFit: gridFit,
      areas: areas,
      columnSizes: columnSizes,
      rowSizes: rowSizes,
      rowGap: rowGap,
      columnGap: columnGap,
      textDirection: textDirection,
      children: childrenWithBoundaries,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);

    properties.add(IterableProperty(
      'columnSizes',
      columnSizes,
    ));
    properties.add(IterableProperty(
      'rowSizes',
      rowSizes,
    ));
    properties.add(DiagnosticsProperty('autoPlacement', autoPlacement));
    properties.add(DiagnosticsProperty('gridFit', gridFit));
    properties.add(DoubleProperty('columnGap', columnGap));
    properties.add(DoubleProperty('rowGap', rowGap));
    properties.add(DiagnosticsProperty('addRepaintBoundaries', addRepaintBoundaries));
    if (textDirection != null) {
      properties.add(DiagnosticsProperty('textDirection', textDirection));
    }
  }
}

class _LayoutGrid extends MultiChildRenderObjectWidget {
  const _LayoutGrid({
    this.autoPlacement = AutoPlacement.rowSparse,
    this.gridFit = GridFit.expand,
    this.areas,
    required this.columnSizes,
    required this.rowSizes,
    this.rowGap = 0,
    this.columnGap = 0,
    this.textDirection,
    super.children,
  });

  final AutoPlacement autoPlacement;
  final GridFit gridFit;
  final String? areas;
  final List<TrackSize> columnSizes;
  final List<TrackSize> rowSizes;
  final double columnGap;
  final double rowGap;
  final TextDirection? textDirection;

  @override
  RenderLayoutGrid createRenderObject(BuildContext context) {
    return RenderLayoutGrid(
      autoPlacement: autoPlacement,
      gridFit: gridFit,
      areasSpec: areas,
      columnSizes: columnSizes,
      rowSizes: rowSizes,
      columnGap: columnGap,
      rowGap: rowGap,
      textDirection: textDirection ?? Directionality.of(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderLayoutGrid renderObject) {
    renderObject
      ..autoPlacement = autoPlacement
      ..gridFit = gridFit
      ..areasSpec = areas
      ..columnSizes = columnSizes
      ..rowSizes = rowSizes
      ..columnGap = columnGap
      ..rowGap = rowGap
      ..textDirection = textDirection ?? Directionality.of(context);
  }
}
