import 'package:saber/data/tools/_tool.dart';
import 'package:sbn/tool_id.dart';

/// A tool that pans the canvas instead of drawing.
///
/// When this tool is selected, dragging with a stylus (or any other
/// pointer) scrolls the page rather than drawing a stroke, so that the
/// user can move around the note without putting the pen down.
class Hand extends Tool {
  new _();

  static final _currentHand = Hand._();
  static Hand get currentHand => _currentHand;

  @override
  ToolId get toolId => .hand;
}
