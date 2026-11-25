import 'dart:async';

import '../../core/auth/auth_session.dart';
import '../../core/auth/credential_store.dart';
import '../../core/network/in_flight_request.dart';
import '../../core/network/mail_client.dart';
import 'mail_cache.dart';

/// The inbox is fetched in full by Coremail. Each caller can take the slice
/// it needs from the same request.
class MailFeed {
  MailFeed(
    this.session, {
    required this.credentials,
    this.isCurrent,
    MailCache? cache,
    Future<MailClient> Function(AuthSession)? fromSession,
  }) : _fromSession = fromSession ?? MailClient.fromSession,
       _cache = cache ?? MailCache.instance;

  final AuthSession session;
  final MailCache _cache;
  final CredentialStore credentials;
  final bool Function()? isCurrent;
  final Future<MailClient> Function(AuthSession) _fromSession;
  final _refresh = InFlightRequest<(MailClient, List<MailSummary>)>();
  final _localReadIds = <String>{};
  MailClient? _client;
  bool _disposed = false;

  bool get active => !_disposed && isCurrent?.call() != false;

  void dispose() => _disposed = true;

  void _checkCurrent() {
    if (!active) {
      throw StateError('The mail session has ended');
    }
  }

  Future<(MailClient, List<MailSummary>)> refresh() => _refresh.run(() async {
    _checkCurrent();
    var client = _client ??= await _createClient();
    List<MailSummary> items;
    try {
      _checkCurrent();
      items = await client.list();
    } on MailSessionExpired {
      _checkCurrent();
      _client = null;
      client = _client = await _createClient();
      _checkCurrent();
      items = await client.list();
    }
    _checkCurrent();
    items = [
      for (final item in items)
        if (!item.read && _localReadIds.contains(item.id))
          _asRead(item)
        else
          item,
    ];
    unawaited(_cache.save(session.studentId, items));
    return (client, items);
  });

  void markRead(String id) => _localReadIds.add(id);

  Future<MailClient> _createClient() async {
    try {
      return await _fromSession(session);
    } catch (_) {
      _checkCurrent();
      final saved = await credentials.read();
      _checkCurrent();
      final password = saved?.password;
      if (saved == null ||
          saved.username.trim() != session.studentId.trim() ||
          password == null ||
          password.isEmpty) {
        rethrow;
      }
      return MailClient.fromCredentials(
        username: saved.username,
        password: password,
      );
    }
  }

  MailSummary _asRead(MailSummary item) => MailSummary(
    id: item.id,
    subject: item.subject,
    from: item.from,
    to: item.to,
    receivedDate: item.receivedDate,
    read: true,
    hasAttachment: item.hasAttachment,
  );
}
