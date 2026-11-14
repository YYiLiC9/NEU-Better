import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/features/mail/mail_attachment_saver.dart';

void main() {
  group('sanitizeFileName', () {
    test('替换非法字符并保留正常名称', () {
      expect(sanitizeFileName('a/b:c*d?.pdf'), 'a_b_c_d_.pdf');
    });

    test('去除控制字符并以点结尾裁剪', () {
      expect(sanitizeFileName(' 报告\u0001.docx. '), '报告.docx');
    });

    test('空名回退为「附件」', () {
      expect(sanitizeFileName('   '), '附件');
    });

    test('过长名称截断但保留扩展名', () {
      final long = '${'a' * 200}.pdf';
      final result = sanitizeFileName(long);
      expect(result.length, lessThanOrEqualTo(150));
      expect(result.endsWith('.pdf'), isTrue);
    });
  });

  group('mimeForFileName', () {
    test('按后缀推断常用类型', () {
      expect(mimeForFileName('a.pdf'), 'application/pdf');
      expect(mimeForFileName('a.DOCX'), contains('wordprocessingml'));
      expect(mimeForFileName('a.zip'), 'application/zip');
    });

    test('无后缀时用声明的非通用类型', () {
      expect(
        mimeForFileName('附件', declared: 'image/png'),
        'image/png',
      );
      expect(
        mimeForFileName('附件', declared: 'text/plain'),
        'application/octet-stream',
      );
    });
  });

  group('saveAttachmentToDownloads（Windows 逻辑）', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('mail_save_test_');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('写入文件并返回路径', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final path = await saveAttachmentToDownloads(
        fileName: '测试.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
        windowsDownloadsDir: dir,
      );
      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsBytesSync(), bytes);
      expect(path.endsWith('测试.pdf'), isTrue);
    });

    test('同名冲突自动加 (1)', () async {
      final bytes = Uint8List.fromList([9]);
      final first = await saveAttachmentToDownloads(
        fileName: 'a.txt',
        bytes: bytes,
        windowsDownloadsDir: dir,
      );
      final second = await saveAttachmentToDownloads(
        fileName: 'a.txt',
        bytes: bytes,
        windowsDownloadsDir: dir,
      );
      expect(first, isNot(second));
      expect(second.endsWith('a(1).txt'), isTrue);
    });
  });
}
