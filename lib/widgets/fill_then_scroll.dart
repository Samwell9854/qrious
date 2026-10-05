import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// [fill] above [rest], where [rest] takes its natural height and [fill] takes
/// whatever is left of [viewportHeight], but never less than [minFillHeight].
///
/// Meant as the child of a scroll view. When everything fits, the total is exactly
/// [viewportHeight] and nothing scrolls; when it does not, [fill] stops shrinking
/// at its minimum and the view scrolls rather than overflowing.
///
/// A `Column` cannot do this: an `Expanded` inside a scroll view has no height to
/// expand into, and measuring [rest] first is the whole point. Hence a render
/// object, which lays [rest] out before deciding how tall [fill] is.
class FillThenScroll extends MultiChildRenderObjectWidget {
  FillThenScroll({
    super.key,
    required this.viewportHeight,
    required this.minFillHeight,
    required Widget fill,
    required Widget rest,
  }) : super(children: [fill, rest]);

  final double viewportHeight;
  final double minFillHeight;

  @override
  RenderFillThenScroll createRenderObject(BuildContext context) =>
      RenderFillThenScroll(viewportHeight, minFillHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFillThenScroll renderObject,
  ) {
    renderObject
      ..viewportHeight = viewportHeight
      ..minFillHeight = minFillHeight;
  }
}

class _FillParentData extends ContainerBoxParentData<RenderBox> {}

class RenderFillThenScroll extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FillParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FillParentData> {
  RenderFillThenScroll(this._viewportHeight, this._minFillHeight);

  double _viewportHeight;
  set viewportHeight(double value) {
    if (value == _viewportHeight) return;
    _viewportHeight = value;
    markNeedsLayout();
  }

  double _minFillHeight;
  set minFillHeight(double value) {
    if (value == _minFillHeight) return;
    _minFillHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FillParentData) {
      child.parentData = _FillParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final fill = firstChild!;
    final rest = childAfter(fill)!;

    rest.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    final fillHeight = max(_viewportHeight - rest.size.height, _minFillHeight);
    fill.layout(BoxConstraints.tightFor(width: width, height: fillHeight));

    (fill.parentData! as _FillParentData).offset = Offset.zero;
    (rest.parentData! as _FillParentData).offset = Offset(0, fillHeight);
    size = constraints.constrain(Size(width, fillHeight + rest.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
