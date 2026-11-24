import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/network/mail_client.dart';
import 'package:neu_better_pro/features/mail/mail_poller.dart';
import 'package:neu_better_pro/features/mail/mail_poll_state.dart';

MailSummary _mail(
  String id, {
  bool read = false,
  String subject = '主题',
  String from = '发件人',
}) =>
    MailSummary(
      id: id,
      subject: subject,
      from: from,
      to: '我',
      receivedDate: DateTime(2026, 1, 1),
      read: read,
      hasAttachment: false,
    );

void main() {
  late Directory dir;
  late File file;
  late MailPollState state;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('mail_poll_');
    file = File('${dir.path}/mail_poll_state.json');
    state = MailPollState(candidates: [file]);
    await state.load();
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  MailPoller buildPoller(
    Future<List<MailSummary>> Function() fetch,
    List<String> notified, {
    bool Function()? enabled,
  }) =>
      MailPoller(
        fetch: fetch,
        notify: (title, body) => notified.add(title),
        state: state,
        enabled: enabled,
      );

  test('首次检查只建立基线，不发通知', () async {
    final notified = <String>[];
    final poller = buildPoller(() async => [_mail('1'), _mail('2')], notified);
    await poller.checkOnce();
    expect(notified, isEmpty);
    expect(state.initialized, isTrue);
    expect(state.knownIds, containsAll(<String>['1', '2']));
  });

  test('新未读邮件通知一次，重复检查不再通知', () async {
    var data = <MailSummary>[_mail('1', read: true)];
    final notified = <String>[];
    final poller = buildPoller(() async => data, notified);

    await poller.checkOnce(); // 基线
    expect(notified, isEmpty);

    data = [_mail('2'), _mail('1', read: true)];
    await poller.checkOnce();
    expect(notified, hasLength(1));
    expect(notified.first, contains('新邮件'));

    await poller.checkOnce(); // 同一封不再通知
    expect(notified, hasLength(1));
  });

  test('已读邮件不通知', () async {
    var data = <MailSummary>[];
    final notified = <String>[];
    final poller = buildPoller(() async => data, notified);
    await poller.checkOnce();
    data = [_mail('9', read: true)];
    await poller.checkOnce();
    expect(notified, isEmpty);
  });

  test('多封新邮件聚合为一条通知', () async {
    var data = <MailSummary>[];
    final notified = <String>[];
    final poller = buildPoller(() async => data, notified);
    await poller.checkOnce();
    data = [_mail('1'), _mail('2'), _mail('3')];
    await poller.checkOnce();
    expect(notified, hasLength(1));
    expect(notified.first, contains('3 封新邮件'));
  });

  test('关闭通知时不 fetch 也不通知', () async {
    var fetchCount = 0;
    final notified = <String>[];
    final poller = buildPoller(
      () async {
        fetchCount++;
        return [_mail('1')];
      },
      notified,
      enabled: () => false,
    );
    await poller.checkOnce();
    expect(fetchCount, 0);
    expect(notified, isEmpty);
  });

  test('fetch 失败不更新基线（下次仍可正常通知）', () async {
    var fail = true;
    var data = <MailSummary>[];
    final notified = <String>[];
    final poller = buildPoller(() async {
      if (fail) throw Exception('网络错误');
      return data;
    }, notified);

    await poller.checkOnce(); // 失败：仍未初始化
    expect(state.initialized, isFalse);

    fail = false;
    data = [_mail('1')];
    await poller.checkOnce(); // 首次成功 → 建立基线
    expect(state.initialized, isTrue);
    expect(notified, isEmpty);

    data = [_mail('1'), _mail('2')];
    await poller.checkOnce();
    expect(notified, hasLength(1));
  });

  test('knownIds 上限 200', () async {
    final notified = <String>[];
    final poller = buildPoller(
      () async => [for (var i = 0; i < 250; i++) _mail('$i')],
      notified,
    );
    await poller.checkOnce();
    expect(state.knownIds.length, lessThanOrEqualTo(MailPollState.maxKnownIds));
  });

  test('状态可持久化并在新实例恢复', () async {
    final notified = <String>[];
    final poller = buildPoller(() async => [_mail('1')], notified);
    await poller.checkOnce();

    final restored = MailPollState(candidates: [file]);
    await restored.load();
    expect(restored.initialized, isTrue);
    expect(restored.knownIds, contains('1'));
  });
}
