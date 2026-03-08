import 'package:flutter/rendering.dart';

import '../foundation/placement.dart';

/// Parent data for use with `RenderLayoutGrid`.
class GridParentData extends ContainerBoxParentData<RenderBox> {
  GridParentData({
    this.columnStart,
    this.columnSpan = 1,
    this.rowStart,
    this.rowSpan = 1,
    this.debugLabel,
  });

  /// If `null`, the item is auto-placed.
  int? columnStart;
  int? columnSpan;

  /// If `null`, the item is auto-placed.
  int? rowStart;
  int? rowSpan;

  String? _areaName;

  String? debugLabel;

  String? get areaName => _areaName;
  set areaName(String? value) {
    if (value == _areaName) {
      return;
    }

    _areaName = value;
    columnStart = rowStart = null;

    // If an area name has been specified, we mark the data as needing area
    // resolution, and null out all fields.
    if (value != null) {
      columnSpan = rowSpan = null;
    } else {
      // If no area name has been specified, we reset the data to base state.
      // These values are likely to be overwritten momentarily.
      columnSpan = rowSpan = 1;
    }
  }

  int? startForAxis(Axis axis) =>
      axis == Axis.horizontal ? columnStart : rowStart;

  int? spanForAxis(Axis axis) => //
      axis == Axis.horizontal ? columnSpan : rowSpan;

  GridArea get area {
    assert(isDefinitelyPlaced);
    return GridArea(
      name: areaName,
      columnStart: columnStart!,
      columnEnd: columnStart! + columnSpan!,
      rowStart: rowStart!,
      rowEnd: rowStart! + rowSpan!,
    );
  }

  set area(GridArea? value) {
    // If null, clear out all track starts/spans
    if (value == null) {
      columnStart = columnSpan = rowStart = rowSpan = null;
    }
    // Otherwise set the specifics
    else {
      columnStart = value.columnStart;
      columnSpan = value.columnSpan;
      rowStart = value.rowStart;
      rowSpan = value.rowSpan;
    }
  }

  /// `true` if the item is placed in the grid, whether definitely or through
  /// the auto-flow algorithm.
  bool get isPlaced => !isNotPlaced;

  /// `true` if the item is not placed in the grid at all (probably because
  /// it references a named area that does not exist).
  bool get isNotPlaced =>
      columnStart == null &&
      columnSpan == null &&
      rowStart == null &&
      rowSpan == null;

  /// `true` if the item has definite placement in the grid.
  bool get isDefinitelyPlaced => columnStart != null && rowStart != null;

  /// `true` if the item is definitely placed on the provided axis.
  bool isDefinitelyPlacedOnAxis(Axis axis) =>
      axis == Axis.horizontal ? columnStart != null : rowStart != null;

  @override
  String toString() {
    final List<String> values = <String>[
      if (areaName != null) 'areaName=$areaName',
      if (columnStart != null) 'columnStart=$columnStart',
      if (columnSpan != null) 'columnSpan=$columnSpan',
      if (rowStart != null) 'rowStart=$rowStart',
      if (rowSpan != null) 'rowSpan=$rowSpan',
      if (debugLabel != null) 'debugLabel=$debugLabel',
    ];
    values.add(super.toString());
    return values.join('; ');
  }
}
