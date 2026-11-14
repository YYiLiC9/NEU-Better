import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:neu_better_pro/core/network/mail_client.dart';
import 'package:neu_better_pro/features/mail/mail_format.dart';

void main() {
  group('MailClient.parseListResponse', () {
    test('解析收件箱列表字段', () {
      const body = '{"code":"S_OK","var":['
          '{"id":"1001","subject":"欢迎使用东北大学学生电子邮件系统",'
          '"from":"东北大学 <mail@neu.edu.cn>",'
          '"to":"杨逸伦 <2672281@stu.neu.edu.cn>",'
          '"receivedDate":1731000000000,"flags":{"read":false},'
          '"attachments":[{"name":"说明.pdf"}]},'
          '{"id":"1002","subject":"已读无附件",'
          '"from":[{"name":"张三","email":"zhang@neu.edu.cn"}],'
          '"to":[{"name":"李四","email":"li@neu.edu.cn"}],'
          '"sentDate":1730800000000,"flags":{"read":true}}'
          ']}';

      final items = MailClient.parseListResponse(body);
      expect(items, hasLength(2));

      final first = items.first;
      expect(first.id, '1001');
      expect(first.subject, '欢迎使用东北大学学生电子邮件系统');
      expect(first.from, '东北大学 <mail@neu.edu.cn>');
      expect(first.to, '杨逸伦 <2672281@stu.neu.edu.cn>');
      expect(first.read, isFalse);
      expect(first.hasAttachment, isTrue);
      expect(first.receivedDate, isNotNull);

      final second = items[1];
      expect(second.subject, '已读无附件');
      expect(second.from, '张三 <zhang@neu.edu.cn>');
      expect(second.read, isTrue);
      expect(second.hasAttachment, isFalse);
      expect(second.receivedDate, isNotNull);
    });

    test('空列表', () {
      expect(MailClient.parseListResponse('{"code":"S_OK","var":[]}'),
          isEmpty);
    });

    test('业务错误抛 MailException', () {
      expect(
        () => MailClient.parseListResponse('{"code":"FA_INVALID_ARGUMENT"}'),
        throwsA(isA<MailException>()),
      );
    });

    test('会话失效抛 MailSessionExpired', () {
      expect(
        () => MailClient.parseListResponse('{"code":"FA_SECURITY"}'),
        throwsA(isA<MailSessionExpired>()),
      );
      expect(
        () => MailClient.parseListResponse('{"code":"FR_INVALID_SESSION"}'),
        throwsA(isA<MailSessionExpired>()),
      );
    });

    test('非 JSON 抛 MailException', () {
      expect(
        () => MailClient.parseListResponse('<html>oops</html>'),
        throwsA(isA<MailException>()),
      );
    });
  });

  group('MailClient.parseDetailResponse', () {
    test('解析读信元数据与附件', () {
      const body = '{"code":"S_OK","var":{'
          '"subject":"关于选课的通知",'
          '"from":[{"name":"教务处","email":"jwc@neu.edu.cn"}],'
          '"to":[{"name":"杨逸伦","email":"2672281@stu.neu.edu.cn"}],'
          '"sentDate":1731000000000,'
          '"html":{"id":"h1","contentType":"text/html"},'
          '"attachments":[{"name":"课表.pdf","size":2048},'
          '{"name":"通知.docx"}]}}';

      final detail = MailClient.parseDetailResponse(body);
      expect(detail.subject, '关于选课的通知');
      expect(detail.from, '教务处 <jwc@neu.edu.cn>');
      expect(detail.to, '杨逸伦 <2672281@stu.neu.edu.cn>');
      expect(detail.date, isNotNull);
      expect(detail.attachments, hasLength(2));
      expect(detail.attachments.first.name, '课表.pdf');
      expect(detail.attachments.first.size, 2048);
      expect(detail.attachments.last.name, '通知.docx');
    });
  });

  group('formatMailDate', () {
    final now = DateTime(2026, 11, 14, 15, 30);

    test('今天显示 HH:mm', () {
      expect(formatMailDate(DateTime(2026, 11, 14, 9, 5), now: now), '09:05');
    });

    test('今年其他日期显示 MM-dd HH:mm', () {
      expect(
        formatMailDate(DateTime(2026, 3, 5, 8, 0), now: now),
        '03-05 08:00',
      );
    });

    test('往年显示 yyyy-MM-dd', () {
      expect(formatMailDate(DateTime(2025, 12, 31), now: now), '2025-12-31');
    });

    test('空值返回空串', () {
      expect(formatMailDate(null), '');
    });
  });

  test('formatMailSize', () {
    expect(formatMailSize(null), '');
    expect(formatMailSize(512), '512 B');
    expect(formatMailSize(2048), '2.0 KB');
    expect(formatMailSize(1024 * 1024 * 3), '3.0 MB');
  });

  test('sortSummariesByDateDesc 最新在上、空日期置后、稳定', () {
    MailSummary mail(String id, DateTime? date) => MailSummary(
          id: id,
          subject: 's$id',
          from: 'f$id',
          to: 't',
          receivedDate: date,
          read: true,
          hasAttachment: false,
        );
    final items = [
      mail('old', DateTime(2024, 1, 1)),
      mail('none', null),
      mail('new', DateTime(2024, 6, 1)),
      mail('mid', DateTime(2024, 3, 1)),
    ];
    final sorted = MailClient.sortSummariesByDateDesc(items);
    expect(sorted.map((m) => m.id).toList(), ['new', 'mid', 'old', 'none']);
    // 不修改入参。
    expect(items.first.id, 'old');
  });

  group('MIME 解析（离线）', () {
    test('multipart/alternative + base64 中文 HTML', () {
      const htmlText = '<p>你好，欢迎使用<b>东北大学</b>邮件系统</p>';
      const plainText = '你好，欢迎使用东北大学邮件系统';
      final b64Html = base64.encode(utf8.encode(htmlText));
      final b64Plain = base64.encode(utf8.encode(plainText));
      final subjectWord =
          '=?UTF-8?B?${base64.encode(utf8.encode('邮件主题'))}?=';
      final raw = 'From: "东北大学" <mail@neu.edu.cn>\r\n'
          'Subject: $subjectWord\r\n'
          'MIME-Version: 1.0\r\n'
          'Content-Type: multipart/mixed; boundary="BOUND"\r\n'
          '\r\n'
          '--BOUND\r\n'
          'Content-Type: multipart/alternative; boundary="ALT"\r\n'
          '\r\n'
          '--ALT\r\n'
          'Content-Type: text/plain; charset=UTF-8\r\n'
          'Content-Transfer-Encoding: base64\r\n'
          '\r\n'
          '$b64Plain\r\n'
          '--ALT\r\n'
          'Content-Type: text/html; charset=UTF-8\r\n'
          'Content-Transfer-Encoding: base64\r\n'
          '\r\n'
          '$b64Html\r\n'
          '--ALT--\r\n'
          '--BOUND--\r\n';

      final mime = MailClient.parseMime(raw);
      expect(mime.isHtml, isTrue);
      expect(mime.body, contains('东北大学'));
      expect(mime.body, contains('<b>'));
      expect(mime.subject, '邮件主题');

      final text = stripHtmlToText(mime.body);
      expect(text, contains('东北大学邮件系统'));
      expect(text, isNot(contains('<b>')));
    });

    test('quoted-printable 纯文本', () {
      const original = '你好，这是测试正文';
      final qp = utf8
          .encode(original)
          .map((b) => '=${b.toRadixString(16).padLeft(2, '0').toUpperCase()}')
          .join();
      final raw = 'Content-Type: text/plain; charset=UTF-8\r\n'
          'Content-Transfer-Encoding: quoted-printable\r\n'
          '\r\n'
          '$qp\r\n';

      final mime = MailClient.parseMime(raw);
      expect(mime.isHtml, isFalse);
      expect(mime.body.trim(), original);
    });

    test('纯 text/plain 直接返回', () {
      const body = '这是一封纯文本邮件。';
      final raw = 'Content-Type: text/plain; charset=UTF-8\r\n'
          'Content-Transfer-Encoding: 7bit\r\n'
          '\r\n'
          '$body\r\n';

      final mime = MailClient.parseMime(raw);
      expect(mime.isHtml, isFalse);
      expect(mime.body.trim(), body);
    });

    test('stripHtmlToText 去标签并解码实体', () {
      const html =
          '<div>第一行<br>第二行 &amp; <b>加粗</b>&nbsp;&#65;&#x42;</div>'
          '<style>.x{color:red}</style><script>alert(1)</script>';
      final text = stripHtmlToText(html);
      expect(text, contains('第一行'));
      expect(text, contains('第二行'));
      expect(text, contains('加粗'));
      expect(text, contains('A'));
      expect(text, contains('B'));
      expect(text, isNot(contains('<b>')));
      expect(text, isNot(contains('alert(1)')));
      expect(text, isNot(contains('color:red')));
    });

    test('GBK quoted-printable 中文正确解码', () {
      final raw = 'Content-Type: text/html; charset=GBK\r\n'
          'Content-Transfer-Encoding: quoted-printable\r\n'
          '\r\n'
          '=BB=B6=D3=AD=CA=B9=D3=C3=B6=AB=B1=B1=B4=F3=D1=A7<br>\r\n';

      final mime = MailClient.parseMime(raw);
      expect(mime.body, contains('欢迎使用东北大学'));
      expect(stripHtmlToText(mime.body), contains('欢迎使用东北大学'));
    });

    test('无正文的 MIME 返回空', () {
      final mime = MailClient.parseMime(
        'Content-Type: multipart/mixed; boundary="B"\r\n\r\n--B--\r\n',
      );
      expect(mime.body.trim(), '');
    });
  });
}
