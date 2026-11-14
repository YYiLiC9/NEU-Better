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
}
