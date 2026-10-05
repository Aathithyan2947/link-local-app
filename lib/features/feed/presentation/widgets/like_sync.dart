/// The like state behind one heart — a post's or a comment's.
///
/// A tap flips the heart and count at once. Only one request is in flight at a time; taps
/// made meanwhile just move the wanted state, and when the request lands the latest wanted
/// state is sent if it differs from what the server now holds. So any burst of taps ends
/// in exactly one final state on the server, never a stack of likes. If the server refuses,
/// the heart goes back to the last state it confirmed.
class LikeSync {
  LikeSync({required bool liked, required int likes, required this.send, required this.onChanged, this.onError})
    : _liked = liked,
      _likes = likes,
      _serverLiked = liked,
      _serverLikes = likes;

  /// Sets the like to the given state on the server; returns what it now holds.
  final Future<({bool liked, int likes})> Function(bool liked) send;

  /// Called whenever [liked] or [likes] change, so the widget can repaint.
  final void Function() onChanged;

  /// Called when the server refuses (e.g. a non-member, or offline).
  final void Function(Object error)? onError;

  bool _liked;
  int _likes;
  bool _serverLiked;
  int _serverLikes;
  bool _inFlight = false;
  bool _disposed = false;

  bool get liked => _liked;
  int get likes => _likes;

  /// Adopts fresh server data (e.g. after a refetch) unless a change is still being sent.
  void reset({required bool liked, required int likes}) {
    if (_inFlight || _liked != _serverLiked) return;
    _liked = _serverLiked = liked;
    _likes = _serverLikes = likes;
  }

  void tap() {
    _liked = !_liked;
    _likes += _liked ? 1 : -1;
    if (_likes < 0) _likes = 0;
    onChanged();
    _flush();
  }

  Future<void> _flush() async {
    if (_inFlight) return;
    while (!_disposed && _liked != _serverLiked) {
      _inFlight = true;
      final wanted = _liked;
      try {
        final r = await send(wanted);
        _serverLiked = r.liked;
        _serverLikes = r.likes;
        // Only take the server's count when the user hasn't tapped again meanwhile.
        if (_liked == wanted) _likes = r.likes;
      } catch (e) {
        _liked = _serverLiked;
        _likes = _serverLikes;
        _inFlight = false;
        if (!_disposed) {
          onChanged();
          onError?.call(e);
        }
        return;
      }
      _inFlight = false;
    }
    if (!_disposed) onChanged();
  }

  /// Stops callbacks once the owning widget is gone; an in-flight request still completes.
  void dispose() => _disposed = true;
}
