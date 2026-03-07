import 'package:flutter/rendering.dart';
import 'package:flutter_layout_grid/src/widgets/layout_grid.dart';

extension LayoutGridExtensionsForBoxConstraints on BoxConstraints {
  /// Returns a new [BoxConstraints] with unbounded (infinite) maximums.
  BoxConstraints get unbound =>
      copyWith(maxWidth: double.infinity, maxHeight: double.infinity);

  /// Returns a new [BoxConstraints] tightening or loosening the receiver as
  /// specified by [gridFit].
  BoxConstraints constraintsForGridFit(GridFit gridFit) {
    return switch (gridFit) {
      GridFit.expand => BoxConstraints.tightForFinite(
          width: biggest.width,
          height: biggest.height,
        ),
      GridFit.loose => loosen(),
      GridFit.passthrough => this,
    };
  }
}
