/// Coordinates hydration and persistence of the latest snapshot for an account.
class AccountSnapshotCache<T> {
  final _accounts = <String, _Snapshot<T>>{};

  T? dataFor(String account) => _accounts[account]?.data;

  Future<T?> load(String account, Future<T?> Function() read) {
    final entry = _accounts.putIfAbsent(account, _Snapshot<T>.new);
    if (entry.loaded) return Future.value(entry.data);
    return entry.reading ??= read()
        .then((data) {
          if (!entry.loaded) entry.data = data;
          entry.loaded = true;
          return entry.data;
        })
        .whenComplete(() => entry.reading = null);
  }

  Future<void> save(String account, T data, Future<void> Function() write) {
    final entry = _accounts.putIfAbsent(account, _Snapshot<T>.new);
    entry.data = data;
    entry.loaded = true;
    return entry.enqueue(write);
  }

  Future<void> clear(String account, Future<void> Function() delete) {
    final entry = _accounts.putIfAbsent(account, _Snapshot<T>.new);
    entry.data = null;
    entry.loaded = true;
    return entry.enqueue(delete);
  }
}

class _Snapshot<T> {
  T? data;
  bool loaded = false;
  Future<T?>? reading;
  Future<void> _pendingWrite = Future.value();

  Future<void> enqueue(Future<void> Function() write) {
    return _pendingWrite = _pendingWrite.then(
      (_) => write(),
      onError: (Object _, StackTrace _) => write(),
    );
  }
}
