/// Coalesces streaming UI repaints during token generation.
///
/// Every streamed chunk currently triggers a full `setState` + markdown
/// re-layout + scroll. On GPU inference tokens arrive in bursts, starving
/// the UI thread (SurfaceFlinger `QueueBuffer timeout`, dropped buffers).
/// This gate allows at most one repaint per [interval] while chunks stream
/// and always paints the final chunk, so no text is ever lost.
class StreamPaintThrottle {
  StreamPaintThrottle({this.interval = const Duration(milliseconds: 150)});

  final Duration interval;

  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

  bool shouldPaint({required bool isFinal, DateTime? now}) {
    final DateTime current = now ?? DateTime.now();
    if (!isFinal && current.difference(_lastPaint) < interval) {
      return false;
    }
    _lastPaint = current;

    return true;
  }
}
