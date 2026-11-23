import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/update/update_service.dart';

void main() {
  test('download resumes from partial file with HTTP Range', () async {
    final bytes = List<int>.generate(256 * 1024, (i) => i % 251);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      var start = 0;
      if (range != null && range.startsWith('bytes=')) {
        start = int.tryParse(range.substring(6).split('-').first) ?? 0;
      }
      if (start > 0) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${bytes.length - 1}/${bytes.length}',
        );
      } else {
        request.response.statusCode = HttpStatus.ok;
      }
      request.response.headers.contentLength = bytes.length - start;
      request.response.add(bytes.sublist(start));
      await request.response.close();
    });

    final dir = await Directory.systemTemp.createTemp('update_resume_test');
    final target = File('${dir.path}/package.zip');
    // 预置半包，模拟上次下载被中断。
    await target.writeAsBytes(bytes.sublist(0, 100 * 1024));

    final service = UpdateService();
    await service.download(
      'http://127.0.0.1:${server.port}/file',
      target,
      expectedSize: bytes.length,
      dio: Dio(),
    );

    expect(await target.length(), bytes.length);
    expect(UpdateInfo.isCompletePackage(target, bytes.length), isTrue);

    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  test('downloadDirectory path is stable by platform', () {
    final dir = UpdateInfo.downloadDirectory(android: false);
    expect(dir.path, contains('neu_better_updates'));
    final apk = UpdateInfo.packageFile('9.9.9', android: true);
    expect(apk.path, endsWith('NEU-Better-9.9.9.apk'));
  });
}
