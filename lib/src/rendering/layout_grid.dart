import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../foundation/box.dart';
import '../foundation/placement.dart';
import '../widgets/layout_grid.dart';
import 'debug.dart';
import 'placement.dart';
import 'track_size.dart';
import 'grid_parent_data.dart';
import 'grid_sizing_info.dart';

/// A [RenderBox] that implements the grid layout algorithm.
///
/// The layout algorithm is a high-performance approximation of the CSS Grid
/// Layout spec, specifically optimized for Flutter's rendering pipeline. It
/// supports fixed, flexible, and intrinsic track sizing, along with named
/// grid areas and automatic item placement.
class RenderLayoutGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, GridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, GridParentData>,
        DebugOverflowIndicatorMixin {
  /// Creates a layout grid render object.
  RenderLayoutGrid({
    AutoPlacement autoPlacement = AutoPlacement.rowSparse,
    GridFit gridFit = GridFit.expand,
    List<RenderBox>? children,
    double columnGap = 0,
    double rowGap = 0,
    String? areasSpec,
    required List<TrackSize> columnSizes,
    required List<TrackSize> rowSizes,
    required TextDirection textDirection,
  })  : _autoPlacementMode = autoPlacement,
        _gridFit = gridFit,
        _columnSizes = columnSizes,
        _rowSizes = rowSizes,
        _areasSpec = areasSpec,
        _areas = areasSpec != null ? parseNamedAreasSpec(areasSpec) : null,
        _columnGap = columnGap,
        _rowGap = rowGap,
        _textDirection = textDirection {
    if (_areas != null) {
      assert(_areas!.columnCount == _columnSizes.length,
          'Number of columns in areas does not match columnSizes');
      assert(_areas!.rowCount == _rowSizes.length,
          'Number of rows in areas does not match rowSizes');
    }
    addAll(children);
  }

  @visibleForTesting
  bool needsPlacement = true;
  late PlacementGrid _placementGrid;

  /// The row and column sizing information calculated during the previous
  /// grid layout pass.
  late GridSizingInfo lastGridSizing;

  /// The union of children contained in this grid. Only set during debug
  /// builds.
  late Rect _debugChildRect;

  /// Controls how the auto-placement algorithm works, specifying exactly how
  /// auto-placed items get flowed into the grid.
  AutoPlacement get autoPlacement => _autoPlacementMode;
  AutoPlacement _autoPlacementMode;
  set autoPlacement(AutoPlacement value) {
    if (_autoPlacementMode == value) return;
    _autoPlacementMode = value;
    markNeedsPlacement();
    markNeedsLayout();
  }

  /// Determines the constraints available to the grid layout algorithm.
  GridFit get gridFit => _gridFit;
  GridFit _gridFit;
  set gridFit(GridFit value) {
    if (_gridFit == value) return;
    _gridFit = value;
    // Placement is not required
    markNeedsLayout();
  }

  /// The string representation of [areas].
  String? get areasSpec => _areasSpec;
  String? _areasSpec;
  set areasSpec(String? value) {
    if (_areasSpec == value) return;
    _areasSpec = value;

    final parsedAreas = value != null ? parseNamedAreasSpec(value) : null;
    if (parsedAreas != null) {
      assert(parsedAreas.columnCount == columnSizes.length,
          'Number of columns in areas does not match columnSizes');
      assert(parsedAreas.rowCount == rowSizes.length,
          'Number of rows in areas does not match rowSizes');
    }
    areas = parsedAreas;
  }

  /// Named areas that can be used for placement.
  NamedGridAreas? get areas => _areas;
  NamedGridAreas? _areas;
  set areas(NamedGridAreas? value) {
    if (_areas == value) return;
    _areas = value;
    markNeedsPlacement();
    markNeedsLayout();
  }

  /// Defines the sizing functions of the grid's columns.
  List<TrackSize> get columnSizes => _columnSizes;
  List<TrackSize> _columnSizes;
  set columnSizes(List<TrackSize> value) {
    if (trackSizeListsEqual(_columnSizes, value)) return;

    // No placement required if the number of columns is the same
    if (value.length != _columnSizes.length) markNeedsPlacement();

    markNeedsLayout();
    _columnSizes = value;
  }

  /// Defines the sizing functions of the grid's rows.
  List<TrackSize> get rowSizes => _rowSizes;
  List<TrackSize> _rowSizes;
  set rowSizes(List<TrackSize> value) {
    if (trackSizeListsEqual(_rowSizes, value)) return;

    // No placement required if the number of rows is the same
    if (value.length != _rowSizes.length) markNeedsPlacement();

    markNeedsLayout();

    _rowSizes = value;
  }

  /// The space between column tracks
  double get columnGap => _columnGap;
  double _columnGap;
  set columnGap(double value) {
    if (_columnGap == value) return;
    _columnGap = value;
    markNeedsLayout();
  }

  /// The space between row tracks
  double get rowGap => _rowGap;
  double _rowGap;
  set rowGap(double value) {
    if (_rowGap == value) return;
    _rowGap = value;
    markNeedsLayout();
  }

  /// The text direction with which to resolve column ordering.
  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! GridParentData) {
      child.parentData = GridParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _computeIntrinsicSize(BoxConstraints.tightFor(height: height))
          .minWidthOfTracks;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _computeIntrinsicSize(BoxConstraints(maxHeight: height)).maxTracksWidth;

  @override
  double computeMinIntrinsicHeight(double width) =>
      _computeIntrinsicSize(BoxConstraints.tightFor(width: width))
          .minHeightOfTracks;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _computeIntrinsicSize(BoxConstraints(maxWidth: width)).maxTracksHeight;

  // Intrinsic sizing delegates to the full grid layout algorithm. This is
  // intentional — Flutter's intrinsic sizing protocol requires us to produce
  // a meaningful size given a constraint, and running the full layout algorithm
  // is the only way to correctly account for intrinsic/flexible track sizing.
  GridSizingInfo _computeIntrinsicSize(BoxConstraints constraints) =>
      computeGridSize(constraints);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return defaultComputeDistanceToHighestActualBaseline(baseline);
  }

  List<RenderBox> getChildrenInTrack(TrackType trackType, int trackIndex) {
    var cells = _placementGrid.getCellsInTrack(trackIndex, trackType);
    var occupants = <RenderBox>{};
    for (var cell in cells) {
      if (cell.isOccupied) {
        occupants.addAll(cell.occupants);
      }
    }
    return occupants.toList(growable: false);
  }

  @override
  void performLayout() {
    if (debugPrintGridLayout) {
      debugPrint('Starting grid layout for constraints $constraints, '
          'child constraints ${constraints.constraintsForGridFit(gridFit)}');
    }

    // Size the grid
    final gridSizing = lastGridSizing = computeGridSize(constraints);
    size = gridSizing.gridSize!;

    if (debugPrintGridLayout) {
      debugPrint('Determined track sizes:');

      for (var c = 0; c < gridSizing.columnTracks.length; c++) {
        final columnWidth = gridSizing
            .sizeForArea(GridArea(
              columnStart: c,
              columnEnd: c + 1,
              rowStart: 0,
              rowEnd: 1,
            ))
            .width;
        debugPrint('  column $c: $columnWidth');
      }

      for (var r = 0; r < gridSizing.rowTracks.length; r++) {
        final rowHeight = gridSizing
            .sizeForArea(GridArea(
              columnStart: 0,
              columnEnd: 1,
              rowStart: r,
              rowEnd: r + 1,
            ))
            .height;
        debugPrint('  row $r: $rowHeight');
      }

      debugPrint('Finished track sizing');
    }

    bool shouldComputeChildRect = false;
    assert(() {
      _debugChildRect = Rect.zero;
      shouldComputeChildRect = true;
      return true;
    }());

    // Position and lay out the grid items
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData as GridParentData;
      if (parentData.isPlaced) {
        final area = _placementGrid.itemAreas[child]!;
        final areaRect =
            gridSizing.offsetForArea(area) & gridSizing.sizeForArea(area);

        parentData.offset = areaRect.topLeft;

        child.layout(
          BoxConstraints.loose(areaRect.size),
          // Note that we do not use the parentUsesSize argument, as we already
          // ask for intrinsics sizes from every child that we care about, and
          // that has the same effect of registering the grid for relayout
          // whenever those children change.
          //
          // Unless, that is, we're in a debug mode. Then we do so that we can
          // compute overflow.
          parentUsesSize: shouldComputeChildRect,
        );

        if (shouldComputeChildRect) {
          _debugChildRect =
              _debugChildRect.expandToInclude(areaRect.topLeft & child.size);
        }
      } else if (debugPrintUnplacedChildren) {
        debugPrint('Area "${parentData.areaName}" not found. \n'
            '$child will not be rendered. ($parentData)');
      }

      child = parentData.nextSibling;
    }
  }

  @override
  @visibleForTesting
  Size computeDryLayout(BoxConstraints constraints) {
    return computeGridSize(constraints).gridSize!;
  }

  @visibleForTesting
  GridSizingInfo computeGridSize(
    BoxConstraints gridConstraints, {
    BoxConstraints? childConstraints,
  }) {
    childConstraints ??= gridConstraints.constraintsForGridFit(gridFit);

    // Distribute grid items into cells
    performItemPlacement();

    // Ready an object that contains our sizing information
    final gridSizing = GridSizingInfo.fromTrackSizeFunctions(
      columnSizeFunctions: _columnSizes,
      rowSizeFunctions: _rowSizes,
      textDirection: textDirection,
      columnGap: columnGap,
      rowGap: rowGap,
    );

    // Determine the size of the column tracks
    _performTrackSizing(
      TrackType.column,
      gridSizing,
      constraints: childConstraints,
    );

    // Determine the size of the row tracks
    _performTrackSizing(
      TrackType.row,
      gridSizing,
      constraints: childConstraints,
    );

    // Stretch intrinsics
    _stretchIntrinsicTracks(TrackType.column, gridSizing,
        constraints: childConstraints);
    _stretchIntrinsicTracks(TrackType.row, gridSizing,
        constraints: childConstraints);

    // Constrain the size of the grid to whatever the parent provides. This
    // may overflow children.
    gridSizing.gridSize =
        gridConstraints.constrain(gridSizing.internalGridSize);

    return gridSizing;
  }

  /// Determines where each grid item is positioned in the grid, using the
  /// auto-placement algorithm if necessary.
  void performItemPlacement() {
    if (needsPlacement) {
      needsPlacement = false;
      _placementGrid = computeItemPlacement(this);
    }
  }

  List<GridTrack> _performTrackSizing(
    TrackType typeBeingSized,
    GridSizingInfo gridSizing, {
    BoxConstraints? constraints,
  }) {
    final tracks = _performTrackSizingInternal(typeBeingSized, gridSizing,
        constraints: constraints);
    gridSizing.markTrackTypeSized(typeBeingSized);
    return tracks;
  }

  /// A rough approximation of
  /// https://drafts.csswg.org/css-grid/#algo-track-sizing. There are a bunch of
  /// steps left out because our model is simpler.
  List<GridTrack> _performTrackSizingInternal(
    TrackType typeBeingSized,
    GridSizingInfo gridSizing, {
    BoxConstraints? constraints,
  }) {
    final sizingAxis = measurementAxisForTrackType(typeBeingSized);
    final intrinsicTracks = <GridTrack>[];
    final flexibleTracks = <GridTrack>[];
    final tracks = gridSizing.tracksForType(typeBeingSized);
    final bounds = constraintBoundsForType(constraints, typeBeingSized);
    final totalGapAlongAxis =
        gridSizing.unitGapAlongAxis(sizingAxis) * (tracks.length - 1);
    final initialFreeSpace =
        bounds.max.isFinite ? bounds.max - totalGapAlongAxis : 0.0;
    final isAxisUpperBound = bounds.max.isFinite;

    if (debugPrintGridLayout) {
      debugPrint('${typeBeingSized.name.toUpperCase()} tracks with a '
          'maximum free space of $initialFreeSpace, '
          'isAxisUpperBound=$isAxisUpperBound');
    }

    // 1. Initialize track sizes

    for (int i = 0; i < tracks.length; i++) {
      final track = tracks[i];

      if (track.sizeFunction
          .isFixedForConstraints(typeBeingSized, constraints!)) {
        // Fixed, definite
        final fixedSize =
            track.sizeFunction.minIntrinsicSize(typeBeingSized, const []);
        track.baseSize = track.growthLimit = fixedSize;
      } else if (track.sizeFunction.isFlexible) {
        // Flexible sizing
        track.baseSize = track.growthLimit = 0;
        flexibleTracks.add(track);
      } else {
        // Intrinsic sizing
        track.baseSize = 0;
        track.growthLimit = double.infinity; // Set in next step
        intrinsicTracks.add(track);
      }

      track.growthLimit = math.max(track.growthLimit, track.baseSize);
    }

    // 2. Resolve intrinsic track sizes

    _resolveIntrinsicTrackSizes(typeBeingSized, sizingAxis, tracks,
        intrinsicTracks, gridSizing, constraints);

    // 3. Grow all tracks from their baseSize up to their growthLimit value
    //    until freeSpace is exhausted.

    var axisMinSize = totalGapAlongAxis, axisMaxSize = totalGapAlongAxis;
    for (final track in tracks) {
      assert(!track.isInfinite);
      axisMinSize += track.baseSize;
      axisMaxSize += track.growthLimit;
    }

    double freeSpace = initialFreeSpace - axisMinSize;
    gridSizing.setMinMaxTrackSizesForAxis(axisMinSize, axisMaxSize, sizingAxis);

    if (debugPrintGridLayout) {
      debugPrint('min-max: ${MinMax(axisMinSize, axisMaxSize)}');
      debugPrint('free space: $freeSpace');
    }

    // We're already overflowing
    if (isAxisUpperBound && freeSpace < 0) {
      if (debugPrintGridLayout) debugPrint('Overflowing by $freeSpace');
      return tracks;
    }

    if (isAxisUpperBound && axisMaxSize > axisMinSize) {
      if (debugPrintGridLayout) {
        debugPrint('Can grow within free space');
      }
      freeSpace =
          _distributeFreeSpace(freeSpace, tracks, [], IntrinsicDimension.min);
      if (debugPrintGridLayout) {
        debugPrint('  Finished distribution. Free space is now $freeSpace');
      }
    } else {
      for (final track in tracks) {
        freeSpace -= track.growthLimit - track.baseSize;
        track.baseSize = track.growthLimit;
      }
    }

    // 4. Size flexible tracks to fill remaining space, if any

    if (flexibleTracks.isEmpty || freeSpace <= 0) {
      return tracks;
    }

    // Note: Per the CSS Grid spec, flexible tracks should have a minimum size
    // equal to their content's minimum contribution. This implementation skips
    // that measurement for performance, as it is prohibitively expensive. In
    // practice this means flexible tracks may be sized smaller than their
    // content minimum. See: https://drafts.csswg.org/css-grid/#valdef-grid-template-columns-flex
    final flexFraction =
        _findFlexFactorUnitSize(tracks, flexibleTracks, initialFreeSpace);

    for (final track in flexibleTracks) {
      track.baseSize = flexFraction * track.sizeFunction.flex!;

      freeSpace -= track.baseSize;
      axisMinSize += track.baseSize;
      axisMaxSize += track.baseSize;
    }

    gridSizing.setMinMaxTrackSizesForAxis(axisMinSize, axisMaxSize, sizingAxis);

    return tracks;
  }

  void _resolveIntrinsicTrackSizes(
    TrackType type,
    Axis sizingAxis,
    List<GridTrack> tracks,
    List<GridTrack> intrinsicTracks,
    GridSizingInfo gridSizing,
    BoxConstraints? constraints,
  ) {
    if (intrinsicTracks.isNotEmpty && debugPrintGridLayout) {
      debugPrint('Resolving intrinsic ${type.name} '
          '${type == TrackType.column ? 'widths' : 'heights'} '
          '[${debugTrackIndicesString(intrinsicTracks)}]');
    }

    final itemsInIntrinsicTracks = <RenderBox>{};
    for (final t in intrinsicTracks) {
      itemsInIntrinsicTracks.addAll(getChildrenInTrack(type, t.index));
    }

    final itemsBySpan = groupBy(itemsInIntrinsicTracks, (RenderObject item) {
      return _placementGrid.itemAreas[item as RenderBox]!
          .spanForAxis(sizingAxis);
    });
    final sortedSpans = itemsBySpan.keys.toList()..sort();

    // Iterate over the spans we find in our items list, in ascending order.
    for (int span in sortedSpans) {
      final spanItems = itemsBySpan[span]!;
      // Group items in this span by their starting track index so we can
      // distribute space to each spanned track range independently.
      final spanItemsByTrack = groupBy<RenderBox, int>(
        spanItems,
        (item) => _placementGrid.itemAreas[item]!.startForAxis(sizingAxis),
      );

      // Size all spans containing at least one intrinsic track and zero
      // flexible tracks.
      for (final i in spanItemsByTrack.keys) {
        final spannedTracks = tracks.getRange(i, i + span);
        final spanItemsInTrack = spanItemsByTrack[i];
        final intrinsicTrack =
            spannedTracks.firstWhereOrNull((t) => t.sizeFunction.isIntrinsic);

        // We don't size flexible tracks until later
        if (intrinsicTrack == null ||
            spannedTracks.any((t) => t.sizeFunction.isFlexible)) {
          continue;
        }

        final crossAxis = flipAxis(sizingAxis);
        final crossAxisSizeForItem = gridSizing.isAxisSized(crossAxis)
            ? (RenderBox item) {
                return gridSizing.sizeForAreaOnAxis(
                    _placementGrid.itemAreas[item]!, crossAxis);
              }
            : (RenderBox _) => double.infinity;

        // Calculate the min-size of the spanned items, and distribute the
        // additional space to the spanned tracks' base sizes.
        final minSpanSize = intrinsicTrack.sizeFunction.minIntrinsicSize(
            type, spanItemsInTrack!,
            crossAxisSizeForItem: crossAxisSizeForItem);
        if (debugPrintGridLayout) {
          debugPrint('  min size of '
              '${debugTrackIndicesString(spannedTracks, trackPrefix: true)} '
              '= $minSpanSize');
        }

        _distributeCalculatedSpaceToSpannedTracks(
            minSpanSize, type, spannedTracks, IntrinsicDimension.min);

        // Calculate the max-size of the spanned items, and distribute the
        // additional space to the spanned tracks' growth limits.
        final maxSpanSize = intrinsicTrack.sizeFunction.maxIntrinsicSize(
            type, spanItemsInTrack,
            crossAxisSizeForItem: crossAxisSizeForItem);
        _distributeCalculatedSpaceToSpannedTracks(
            maxSpanSize, type, spannedTracks, IntrinsicDimension.max);
        if (debugPrintGridLayout) {
          debugPrint('  max size of '
              '${debugTrackIndicesString(spannedTracks, trackPrefix: true)} '
              '= $maxSpanSize');
        }
      }
    }

    // The time for infinite growth limits is over!
    for (final track in intrinsicTracks) {
      if (track.isInfinite) track.growthLimit = track.baseSize;

      if (debugPrintGridLayout) {
        debugPrint('  update track ${track.index} = '
            '${track.toPrettySizeString()}');
      }
    }
  }

  /// Distributes free space among [spannedTracks]
  void _distributeCalculatedSpaceToSpannedTracks(
    double calculatedSpace,
    TrackType type,
    Iterable<GridTrack> spannedTracks,
    IntrinsicDimension dimension,
  ) {
    // Subtract calculated dimensions of the tracks
    double freeSpace = calculatedSpace;
    for (final track in spannedTracks) {
      freeSpace -= dimension == IntrinsicDimension.min
          ? track.baseSize
          : track.isInfinite
              ? track.baseSize
              : track.growthLimit;
    }

    // If there's no free space to distribute, freeze the tracks and we're done
    if (freeSpace <= 0) {
      for (final track in spannedTracks) {
        if (track.isInfinite) {
          track.growthLimit = track.baseSize;
        }
      }
      return;
    }

    // Filter to the intrinsicly sized tracks in the span
    final intrinsicTracks = spannedTracks
        .where((track) => track.sizeFunction.isIntrinsic)
        .toList(growable: false);

    // Now distribute the free space between them
    if (intrinsicTracks.isNotEmpty) {
      _distributeFreeSpace(
          freeSpace, intrinsicTracks, intrinsicTracks, dimension);
    }
  }

  double _distributeFreeSpace(
    double freeSpace,
    List<GridTrack> tracks,
    List<GridTrack> growableAboveMaxTracks,
    IntrinsicDimension dimension,
  ) {
    assert(freeSpace >= 0);

    if (debugPrintGridLayout) {
      debugPrint('  distributing $freeSpace across '
          '${debugTrackIndicesString(tracks)} on '
          '${dimension.name}');
    }

    // Grab a mutable copy of our tracks
    tracks = tracks.toList();

    void distribute(
      List<GridTrack> tracks,
      double Function(GridTrack, double) getShareForTrack,
    ) {
      final trackCount = tracks.length;
      for (int i = 0; i < trackCount; i++) {
        final track = tracks[i];
        final availableShare = freeSpace / (trackCount - i);
        final shareForTrack = getShareForTrack(track, availableShare);
        assert(shareForTrack >= 0.0, 'Never shrink a track');

        track.sizeDuringDistribution += shareForTrack;
        freeSpace -= shareForTrack;
      }
    }

    // Setup a size that will be used for distribution calculations, and
    // assigned back to the sizes when we complete.
    for (final track in tracks) {
      track.sizeDuringDistribution = dimension == IntrinsicDimension.min
          ? track.baseSize
          : track.isInfinite
              ? track.baseSize
              : track.growthLimit;
    }

    tracks.sort(sortByGrowthPotential);

    // Distribute the free space between tracks
    distribute(tracks, (track, availableShare) {
      return track.isInfinite
          ? availableShare
          // Grow up until limit
          : math.min(
              availableShare,
              track.growthLimit - track.sizeDuringDistribution,
            );
    });

    // If we still have space leftover, let's unfreeze and grow some more
    // (ignoring limit)
    if (freeSpace > 0 && growableAboveMaxTracks.isNotEmpty) {
      distribute(
          growableAboveMaxTracks, (track, availableShare) => availableShare);
    }

    // Assign back the calculated sizes
    for (final track in tracks) {
      if (dimension == IntrinsicDimension.min) {
        track.baseSize = math.max(track.baseSize, track.sizeDuringDistribution);
      } else {
        track.growthLimit = track.isInfinite
            ? track.sizeDuringDistribution
            : math.max(track.growthLimit, track.sizeDuringDistribution);
      }
    }

    return freeSpace;
  }

  double _findFlexFactorUnitSize(
    List<GridTrack> tracks,
    List<GridTrack> flexibleTracks,
    double freeSpace,
  ) {
    double flexSum = 0;
    for (final track in tracks) {
      if (!track.sizeFunction.isFlexible) {
        freeSpace -= track.baseSize;
      } else {
        flexSum += track.sizeFunction.flex!;
      }
    }

    assert(flexSum > 0);
    // Note: Per spec, we should also consider track base sizes larger than their
    // flex contribution. This is skipped for performance. In practice, this means
    // flex tracks can be allocated less space than their content minimum if their
    // base size exceeds the flex allocation.
    return freeSpace / flexSum;
  }

  /// Expands intrinsic tracks to fill the minimum grid size constraint.
  ///
  /// This is intentionally a separate pass from [_distributeFreeSpace], which
  /// handles flexible track growth. This method specifically handles the case
  /// where the grid's minimum constraint is larger than its content, stretching
  /// only `auto`-sized tracks equally to fill the remaining space.
  void _stretchIntrinsicTracks(
    TrackType type,
    GridSizingInfo gridSizing, {
    required BoxConstraints constraints,
  }) {
    final minimumGridSize = constraintBoundsForType(constraints, type).min;
    final freeSpace = minimumGridSize -
        gridSizing.totalBaseSizeOfTracksForType(type) -
        gridSizing.totalGapForType(type);

    if (freeSpace <= 0) return;

    final tracks = gridSizing.tracksForType(type);
    final intrinsicTracks = tracks.where((t) => t.sizeFunction.isIntrinsic);
    if (intrinsicTracks.isEmpty) return;

    final shareForTrack = freeSpace / intrinsicTracks.length;
    for (final track in intrinsicTracks) {
      track.baseSize += shareForTrack;
    }
    gridSizing.invalidateTrackStartsForType(type);
  }

  @override
  void adoptChild(RenderObject child) {
    super.adoptChild(child);
    markNeedsPlacementIfRequired(child);
  }

  @override
  void dropChild(RenderObject child) {
    super.dropChild(child);
    markNeedsPlacementIfRequired(child);
  }

  /// Determines whether [child] may represent a change in grid item
  /// positioning, and if so, ensures that we will regenerate the placement grid
  /// on next layout.
  void markNeedsPlacementIfRequired(RenderObject child) {
    if (needsPlacement) return;
    final parentData = child.parentData as GridParentData?;
    if (parentData != null && !parentData.isDefinitelyPlaced) {
      markNeedsPlacement();
    }
  }

  void markNeedsPlacement() => needsPlacement = true;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void visitChildrenForSemantics(visitor) {
    var child = firstChild;
    while (child != null) {
      final GridParentData childParentData = child.parentData as GridParentData;
      if (childParentData.isPlaced) {
        visitor(child);
      }
      child = childParentData.nextSibling;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    visitChildrenForSemantics((child) {
      final childParentData = child.parentData as GridParentData;
      context.paintChild(child, childParentData.offset + offset);
    });

    assert(() {
      final gridRect = Offset.zero & size;
      // We massage the child rect a bit to make sure that we aren't marking
      // overflows when they're very minor.
      //
      // The reason this isn't a boolean response is because tiny overflows are
      // common, which is fine, but when one of the edges is overflowing by
      // a meaningful amount, both edges will frequently show the indicator.
      final childRect =
          childRectForOverflowComparison(gridRect, _debugChildRect);
      paintOverflowIndicator(context, offset, gridRect, childRect);

      return true;
    }());
  }

  @override
  void debugPaintSize(PaintingContext context, Offset offset) {
    assert(() {
      super.debugPaintSize(context, offset);

      final gapPaint = Paint()..color = const Color(0x90909090);
      final cellEdgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = const Color(0x90909090);

      var gapPath = Path()..addRect(offset & size);
      for (int c = 0; c < _columnSizes.length; c++) {
        for (int r = 0; r < _rowSizes.length; r++) {
          final cellRect = lastGridSizing.rectForArea(GridArea(
            columnStart: c,
            columnEnd: c + 1,
            rowStart: r,
            rowEnd: r + 1,
          ));

          gapPath = Path.combine(
            PathOperation.difference,
            gapPath,
            Path()..addRect(cellRect.deflate(0.1)),
          );
        }
      }
      final drawGaps = _columnGap != 0 || _rowGap != 0;
      context.canvas.drawPath(gapPath, drawGaps ? gapPaint : cellEdgePaint);

      return true;
    }());
  }
}
