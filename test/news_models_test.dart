import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/core/models/news_models.dart';

void main() {
  group('parseNewsSections', () {
    test('解析分组与子栏目，跳过空字段', () {
      final root = jsonDecode('''
      {
        "e": 0,
        "d": {
          "list": [
            {
              "name": "新闻资讯",
              "children": [
                {"id": "cid-news", "name": "东大要闻", "mid": "news"},
                {"id": "", "name": "空栏目"},
                {"id": "cid-empty-name", "name": "  "}
              ]
            },
            {"name": "通知公告", "children": []}
          ]
        }
      }
      ''');
      final sections = parseNewsSections(root);
      expect(sections, hasLength(1));
      expect(sections.first.id, 'cid-news');
      expect(sections.first.name, '东大要闻');
      expect(sections.first.group, '新闻资讯');
    });

    test('异常结构返回空列表', () {
      expect(parseNewsSections(null), isEmpty);
      expect(parseNewsSections(<String, Object?>{}), isEmpty);
    });
  });

  group('parseNewsList', () {
    test('解析列表、总条数与 picurl 兼容', () {
      final root = jsonDecode('''
      {
        "d": {
          "total": 89,
          "list": [
            {
              "id": "a1",
              "title": "标题一",
              "desc": "摘要",
              "picurl": ["https://img/1.jpg"],
              "publish_date_time": "2026-11-16 10:10",
              "cname": "校内通知",
              "author": "办公室",
              "reader": 12,
              "has_read": false,
              "url": "https://x/1",
              "cid": "c1"
            },
            {
              "id": "a2",
              "title": "标题二",
              "picurl": "https://img/2.jpg",
              "publish_time": "2026-11-15",
              "has_read": true
            }
          ]
        }
      }
      ''');
      final result = parseNewsList(root);
      expect(result.total, 89);
      expect(result.items, hasLength(2));
      final first = result.items.first;
      expect(first.title, '标题一');
      expect(first.picurls, <String>['https://img/1.jpg']);
      expect(first.firstPic, 'https://img/1.jpg');
      expect(first.hasRead, isFalse);
      expect(first.reader, 12);
      expect(first.shortDate, '11-16');
      final second = result.items[1];
      expect(second.picurls, <String>['https://img/2.jpg']);
      expect(second.hasRead, isTrue);
      expect(second.publishTime, '2026-11-15');
    });

    test('picurl 为 JSON 字符串数组', () {
      final root = jsonDecode('''
      {"d": {"list": [{"id": "b1", "title": "t", "picurl": "[\\"https://i/1.jpg\\",\\"https://i/2.jpg\\"]"}]}}
      ''');
      final result = parseNewsList(root);
      expect(result.items.single.picurls, <String>[
        'https://i/1.jpg',
        'https://i/2.jpg',
      ]);
    });
  });

  group('parseNewsDetail', () {
    test('解析正文 HTML 与附件', () {
      final root = jsonDecode('''
      {
        "d": {
          "data": {
            "id": "a1",
            "title": "详情标题",
            "content": "<p>正文</p>",
            "publish_date_time": "2026-11-16 10:10",
            "author": "作者",
            "cname": "校内通知",
            "picurl": "[]",
            "url": "https://x/1",
            "attachment": "[\\"https://x/a.pdf\\"]"
          }
        }
      }
      ''');
      final detail = parseNewsDetail(root);
      expect(detail, isNotNull);
      expect(detail!.title, '详情标题');
      expect(detail.contentHtml, '<p>正文</p>');
      expect(detail.attachments, <String>['https://x/a.pdf']);
      expect(parseNewsDetail(null), isNull);
    });
  });

  group('NewsPrefs', () {
    test('默认仅选校内通知', () {
      final prefs = NewsPrefs.defaults();
      expect(prefs.selectedCids, <String>[NewsPrefs.internalNoticeId]);
    });

    test('normalized 保证校内通知且过滤失效栏目', () {
      const prefs = NewsPrefs(
        selectedCids: <String>['officia1', 'stale', 'officia1'],
      );
      final normalized = prefs.normalized(<String>['officia1']);
      expect(normalized, <String>[NewsPrefs.internalNoticeId, 'officia1']);
    });

    test('toJson / fromJson 往返', () {
      const prefs = NewsPrefs(
        selectedCids: <String>[NewsPrefs.internalNoticeId, 'a'],
      );
      final decoded = NewsPrefs.fromJson(jsonDecode(jsonEncode(prefs.toJson())));
      expect(decoded, isNotNull);
      expect(decoded!.selectedCids, prefs.selectedCids);
      expect(NewsPrefs.fromJson(<String, Object?>{}), isNull);
    });
  });
}
