import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_layout_grid/flutter_layout_grid.dart';

import '../foundation/collections.dart';

MinMax<double> constraintBoundsForType(
    BoxConstraints? constraints, TrackType type) {
  return type == TrackType.column
      ? MinMax(constraints!.minWidth, constraints.maxWidth)
      : MinMax(constraints!.minHeight, constraints.maxHeight);
}

enum IntrinsicDimension { min, max }

class GridTrack {
  GridTrack(this.index, this.sizeFunction);

  final int index;
  final TrackSize sizeFunction;

  double _baseSize = 0;
  double _growthLimit = 0;

  double sizeDuringDistribution = 0;

  double get baseSize => _baseSize;
  set baseSize(double value) {
    _baseSize = value;
    _increaseGrowthLimitIfNecessary();
  }

  double get growthLimit => _growthLimit;
  set growthLimit(double value) {
    _growthLimit = value;
    _increaseGrowthLimitIfNecessary();
  }

  bool get isInfinite => _growthLimit == double.infinity;

  void _increaseGrowthLimitIfNecessary() {
    if (_growthLimit != double.infinity && _growthLimit < _baseSize) {
      _growthLimit = _baseSize;
    }
  }

  @override
  String toString() {
    return 'GridTrack(baseSize=$baseSize, growthLimit=$growthLimit, sizeFunction=$sizeFunction)';
  }

  String toPrettySizeString() {
    return _baseSize == _growthLimit
        ? _baseSize.toStringAsFixed(1)
        : '${_baseSize.toStringAsFixed(1)}->${_growthLimit.toStringAsFixed(1)}';
  }
}

UnmodifiableListView<GridTrack> sizesToTracks(Iterable<TrackSize> sizes) {
  final list = <GridTrack>[];
  int i = 0;
  for (final size in sizes) {
    list.add(GridTrack(i++, size));
  }
  return UnmodifiableListView(list);
}

class GridSizingInfo {
  GridSizingInfo({
    required List<GridTrack> columnTracks,
    required List<GridTrack> rowTracks,
    required this.columnGap,
    required this.rowGap,
    required this.textDirection,
  })  : columnTracks = UnmodifiableListView(columnTracks),
        rowTracks = UnmodifiableListView(rowTracks);

  GridSizingInfo.fromTrackSizeFunctions({
    required List<TrackSize> columnSizeFunctions,
    required List<TrackSize> rowSizeFunctions,
    required TextDirection textDirection,
    double columnGap = 0,
    double rowGap = 0,
  }) : this(
          columnTracks: sizesToTracks(columnSizeFunctions),
          rowTracks: sizesToTracks(rowSizeFunctions),
          textDirection: textDirection,
          columnGap: columnGap,
          rowGap: rowGap,
        );

  Size? gridSize;
  final double columnGap;
  final double rowGap;

  final UnmodifiableListView<GridTrack> columnTracks;
  final UnmodifiableListView<GridTrack> rowTracks;

  final TextDirection textDirection;

  List<double>? _ltrColumnStarts;
  List<double>? get columnStartsWithoutGaps {
    if (_ltrColumnStarts != null) return _ltrColumnStarts;
    final list = List<double>.filled(columnTracks.length, 0.0);
    double current = 0.0;
    for (int i = 0; i < columnTracks.length; i++) {
      list[i] = current;
      current += columnTracks[i].baseSize;
    }
    return _ltrColumnStarts = list;
  }

  List<double>? _rowStarts;
  List<double>? get rowStartsWithoutGaps {
    if (_rowStarts != null) return _rowStarts;
    final list = List<double>.filled(rowTracks.length, 0.0);
    double current = 0.0;
    for (int i = 0; i < rowTracks.length; i++) {
      list[i] = current;
      current += rowTracks[i].baseSize;
    }
    return _rowStarts = list;
  }

  double minWidthOfTracks = 0.0;
  double minHeightOfTracks = 0.0;

  double maxTracksWidth = 0.0;
  double maxTracksHeight = 0.0;

  bool hasColumnSizing = false;
  bool hasRowSizing = false;

  /// The size occupied by the grid's tracks and gaps, without considering the
  /// constraints applied to the grid itself.
  Size get internalGridSize {
    double widthSum = 0.0;
    for (final t in columnTracks) {
      widthSum += t.baseSize;
    }
    final gridWidth = widthSum + columnGap * (columnTracks.length - 1);

    double heightSum = 0.0;
    for (final t in rowTracks) {
      heightSum += t.baseSize;
    }
    final gridHeight = heightSum + rowGap * (rowTracks.length - 1);

    return Size(gridWidth, gridHeight);
  }

  Offset offsetForArea(GridArea area) {
    return Offset(
        textDirection == TextDirection.ltr
            ? columnStartsWithoutGaps![area.columnStart] +
                columnGap * area.columnStart
            : gridSize!.width -
                columnStartsWithoutGaps![area.columnStart] -
                sizeForAreaOnAxis(area, Axis.horizontal) -
                columnGap * area.columnStart,
        rowStartsWithoutGaps![area.rowStart] + rowGap * area.rowStart);
  }

  Size sizeForArea(GridArea area) {
    return Size(
      sizeForAreaOnAxis(area, Axis.horizontal),
      sizeForAreaOnAxis(area, Axis.vertical),
    );
  }

  Rect rectForArea(GridArea area) {
    return offsetForArea(area) & sizeForArea(area);
  }

  void markTrackTypeSized(TrackType type) {
    if (type == TrackType.column) {
      hasColumnSizing = true;
    } else {
      hasRowSizing = true;
    }
  }

  MinMax minMaxTrackSizesForAxis(Axis axis) {
    return axis == Axis.horizontal
        ? MinMax(minWidthOfTracks, maxTracksWidth)
        : MinMax(minHeightOfTracks, maxTracksHeight);
  }

  List<double> baseSizesForType(TrackType type) {
    final tracks = tracksForType(type);
    final result = List<double>.filled(tracks.length, 0.0);
    for (int i = 0; i < tracks.length; i++) {
      result[i] = tracks[i].baseSize;
    }
    return result;
  }

  double totalBaseSizeOfTracksForType(TrackType type) =>
      sum(baseSizesForType(type));

  void setMinMaxTrackSizesForAxis(double min, double max, Axis axis) {
    if (axis == Axis.horizontal) {
      minWidthOfTracks = min;
      maxTracksWidth = max;
    } else {
      minHeightOfTracks = min;
      maxTracksHeight = max;
    }
  }

  double unitGapAlongAxis(Axis axis) =>
      axis == Axis.horizontal ? columnGap : rowGap;

  double unitGapForType(TrackType type) =>
      unitGapAlongAxis(measurementAxisForTrackType(type));

  double totalGapForType(TrackType type) =>
      (tracksForType(type).length - 1) * unitGapForType(type);

  bool isAxisSized(Axis sizingAxis) =>
      sizingAxis == Axis.horizontal ? hasColumnSizing : hasRowSizing;

  List<GridTrack> tracksForType(TrackType type) =>
      type == TrackType.column ? columnTracks : rowTracks;

  List<GridTrack> tracksAlongAxis(Axis sizingAxis) =>
      sizingAxis == Axis.horizontal ? columnTracks : rowTracks;

  double sizeForAreaOnAxis(GridArea area, Axis axis) {
    assert(isAxisSized(axis));

    double trackSum = 0.0;
    final tracks = tracksAlongAxis(axis);
    for (int i = area.startForAxis(axis); i < area.endForAxis(axis); i++) {
      trackSum += tracks[i].baseSize;
    }

    final gapSize = (area.spanForAxis(axis) - 1) * unitGapAlongAxis(axis);
    return math.max(0, trackSum + gapSize);
  }

  void invalidateTrackStartsForType(TrackType type) {
    if (type == TrackType.column) {
      _ltrColumnStarts = null;
    } else {
      _rowStarts = null;
    }
  }
}

int sortByGrowthPotential(GridTrack a, GridTrack b) {
  if (a.isInfinite != b.isInfinite) return a.isInfinite ? -1 : 1;
  return (a.growthLimit - a.baseSize).compareTo(b.growthLimit - b.baseSize);
}

Rect childRectForOverflowComparison(Rect gridRect, Rect childRect) {
  return Rect.fromLTRB(
    gridRect.left - childRect.left < precisionErrorTolerance
        ? gridRect.left
        : childRect.left,
    gridRect.top - childRect.top < precisionErrorTolerance
        ? gridRect.top
        : childRect.top,
    childRect.right - gridRect.right < precisionErrorTolerance
        ? gridRect.right
        : childRect.right,
    childRect.bottom - gridRect.bottom < precisionErrorTolerance
        ? gridRect.bottom
        : childRect.bottom,
  );
}

class MinMax<T extends num> {
  const MinMax(this.min, this.max);
  final T min;
  final T max;

  @override
  String toString() {
    return '${min.toStringAsFixed(1)}->${max.toStringAsFixed(1)}'
        '${min == max ? ' (same)' : ''}';
  }
}
