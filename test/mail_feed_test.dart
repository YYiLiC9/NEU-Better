import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/auth/auth_session.dart';
import 'package:neu_better_pro/core/auth/credential_store.dart';
import 'package:neu_better_pro/core/network/mail_client.dart';
import 'package:neu_better_pro/features/mail/mail_cache.dart';
import 'package:neu_better_pro/features/mail/mail_feed.dart';

class _Inbox extends MailClient {
  _Inbox() : super(const CoremailSession(sid: 'test', cookieHeader: ''));

  var reads = 0;
  var response = Completer<List<MailSummary>>();

  @override
  Future<List<MailSummary>> list({int? limit}) {
    expect(limit, isNull);
    reads++;
    return response.future;
  }
}

void main() {
  test('one inbox request serves all callers and can refresh again', () async {
    final inbox = _Inbox();
    final cache = MailCache(store: MailCacheStore(candidates: []));
    final feed = MailFeed(
      AuthSession(studentId: 'A', cookies: {}, createdAt: DateTime(2026)),
      credentials: const SecureCredentialStore(),
      fromSession: (_) async => inbox,
      cache: cache,
    );
    final first = feed.refresh();
    final second = feed.refresh();
    expect(identical(first, second), isTrue);
    inbox.response.complete([]);
    await Future.wait([first, second]);
    expect(inbox.reads, 1);

    inbox.response = Completer<List<MailSummary>>();
    final lateRequest = feed.refresh();
    feed.dispose();
    inbox.response.complete([
      const MailSummary(
        id: 'late',
        subject: '',
        from: '',
        to: '',
        receivedDate: null,
        read: false,
        hasAttachment: false,
      ),
    ]);
    await expectLater(lateRequest, throwsStateError);
    expect(inbox.reads, 2);
    expect(cache.itemsFor('A'), isEmpty);
  });
}
