/// Shares an unfinished request. A later call can retry or fetch fresh data.
class InFlightRequest<T> {
  Future<T>? _pending;

  Future<T> run(Future<T> Function() request) {
    return _pending ??= Future<T>.sync(request).whenComplete(() {
      _pending = null;
    });
  }
}
