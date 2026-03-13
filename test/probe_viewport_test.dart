
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RenderShrinkWrappingViewport dry layout support test', () {
    final renderBox = RenderShrinkWrappingViewport(
      axisDirection: AxisDirection.down,
      crossAxisDirection: AxisDirection.right,
      offset: ViewportOffset.fixed(0),
    );

    final constraints = BoxConstraints(maxWidth: 300, maxHeight: double.infinity);
    
    print('--- STARTING PROBE ---');
    try {
      print('Testing getDryLayout on RenderShrinkWrappingViewport...');
      // Note: we might need to attach it and perform a minimal setup?
      // For dry layout, computeDryLayout should be enough if implemented.
      final size = renderBox.getDryLayout(constraints);
      print('Success! Size: $size');
    } catch (e) {
      print('Failed to get dry layout: $e');
    }

    try {
      print('Testing getMinIntrinsicHeight...');
      final height = renderBox.getMinIntrinsicHeight(300);
      print('Success! Height: $height');
    } catch (e) {
      print('Failed to get intrinsics: $e');
    }
    print('--- ENDING PROBE ---');
  });
}
