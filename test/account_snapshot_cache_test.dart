import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/storage/account_snapshot_cache.dart';

void main() {
  test('reads an account once and keeps a newer network snapshot', () async {
    final cache = AccountSnapshotCache<String>();
    final disk = Completer<String?>();
    var reads = 0;
    Future<String?> read() {
      reads++;
      return disk.future;
    }

    final first = cache.load('A', read);
    final second = cache.load('A', read);
    await cache.save('A', 'network', () async {});
    disk.complete('disk');

    expect(await first, 'network');
    expect(await second, 'network');
    expect(await cache.load('A', read), 'network');
    expect(reads, 1);
    expect(cache.dataFor('B'), isNull);
  });

  test('logout deletes an account after any pending write', () async {
    final cache = AccountSnapshotCache<String>();
    final write = Completer<void>();
    final operations = <String>[];
    final saving = cache.save('A', 'value', () async {
      await write.future;
      operations.add('write');
    });
    final clearing = cache.clear('A', () async => operations.add('delete'));
    expect(cache.dataFor('A'), isNull);
    write.complete();
    await Future.wait([saving, clearing]);
    expect(operations, ['write', 'delete']);
  });
}
