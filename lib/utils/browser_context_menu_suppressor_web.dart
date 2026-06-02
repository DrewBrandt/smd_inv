import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:ui';

import 'package:web/web.dart' as web;

class BrowserContextMenuSuppressor {
  static final Set<BrowserContextMenuSuppressor> _instances = {};
  static web.EventListener? _contextMenuListener;
  static web.EventListener? _mouseMoveListener;

  static const double _samePositionTolerance = 2;

  Rect? _bounds;
  double? _lastSuppressedX;
  double? _lastSuppressedY;

  BrowserContextMenuSuppressor() {
    _instances.add(this);
    _ensureListeners();
  }

  void updateBounds(Rect? bounds) {
    _bounds = bounds;
  }

  void dispose() {
    _instances.remove(this);
    if (_instances.isEmpty) {
      web.document.removeEventListener('contextmenu', _contextMenuListener);
      web.document.removeEventListener('mousemove', _mouseMoveListener);
      _contextMenuListener = null;
      _mouseMoveListener = null;
    }
  }

  static void _ensureListeners() {
    if (_contextMenuListener == null) {
      _contextMenuListener =
          ((web.Event event) => _handleContextMenu(event)).toJS;
      web.document.addEventListener('contextmenu', _contextMenuListener);
    }
    if (_mouseMoveListener == null) {
      _mouseMoveListener = ((web.Event event) => _handleMouseMove(event)).toJS;
      web.document.addEventListener('mousemove', _mouseMoveListener);
    }
  }

  static void _handleContextMenu(web.Event rawEvent) {
    final event = rawEvent as web.MouseEvent;
    final x = event.clientX.toDouble();
    final y = event.clientY.toDouble();
    final suppressor = _suppressorAt(x, y);
    if (suppressor == null) return;

    if (suppressor._isRepeatAtSamePosition(x, y)) {
      suppressor._clearLastSuppressedPosition();
      return;
    }

    event.preventDefault();
    suppressor._lastSuppressedX = x;
    suppressor._lastSuppressedY = y;
  }

  static void _handleMouseMove(web.Event rawEvent) {
    final event = rawEvent as web.MouseEvent;
    final x = event.clientX.toDouble();
    final y = event.clientY.toDouble();
    for (final suppressor in _instances) {
      final lastX = suppressor._lastSuppressedX;
      final lastY = suppressor._lastSuppressedY;
      if (lastX == null || lastY == null) continue;
      if (_distance(lastX, lastY, x, y) > _samePositionTolerance) {
        suppressor._clearLastSuppressedPosition();
      }
    }
  }

  static BrowserContextMenuSuppressor? _suppressorAt(double x, double y) {
    for (final suppressor in _instances) {
      final bounds = suppressor._bounds;
      if (bounds == null) continue;
      if (bounds.contains(Offset(x, y))) return suppressor;
    }
    return null;
  }

  bool _isRepeatAtSamePosition(double x, double y) {
    final lastX = _lastSuppressedX;
    final lastY = _lastSuppressedY;
    if (lastX == null || lastY == null) return false;
    return _distance(lastX, lastY, x, y) <= _samePositionTolerance;
  }

  void _clearLastSuppressedPosition() {
    _lastSuppressedX = null;
    _lastSuppressedY = null;
  }

  static double _distance(double ax, double ay, double bx, double by) {
    final dx = ax - bx;
    final dy = ay - by;
    return math.sqrt(dx * dx + dy * dy);
  }
}
