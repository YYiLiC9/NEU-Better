import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// 首页卡片尺寸档（单位：高×宽，基于 4 列方形单元网格）。
enum HomeCardSize { s1x1, s2x2, s2x4 }

/// 尺寸档对应的 (rows, cols)。
(int, int) spanOf(HomeCardSize size) {
  switch (size) {
    case HomeCardSize.s1x1:
      return (1, 1);
    case HomeCardSize.s2x2:
      return (2, 2);
    case HomeCardSize.s2x4:
      return (2, 4);
  }
}

/// 首页允许出现的卡片 id（本迭代仅寝室用电 + 通知/邮件占位）。
const List<String> knownHomeCardIds = <String>['dorm', 'notify', 'mail'];

@immutable
class HomeCardLayout {
  const HomeCardLayout({required this.id, required this.size});

  final String id;
  final HomeCardSize size;

  HomeCardLayout copyWith({HomeCardSize? size}) =>
      HomeCardLayout(id: id, size: size ?? this.size);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'size': size.name,
  };

  static HomeCardSize? sizeByName(Object? name) {
    for (final value in HomeCardSize.values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static HomeCardLayout? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id']?.toString() ?? '';
    if (id.trim().isEmpty) return null;
    return HomeCardLayout(
      id: id,
      size: sizeByName(json['size']) ?? HomeCardSize.s1x1,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HomeCardLayout && other.id == id && other.size == size;

  @override
  int get hashCode => Object.hash(id, size);
}

/// 默认首页布局：寝室用电 2×4，通知/邮件 1×1，顺序 [dorm, notify, mail]。
List<HomeCardLayout> defaultHomeCards() => const <HomeCardLayout>[
  HomeCardLayout(id: 'dorm', size: HomeCardSize.s2x4),
  HomeCardLayout(id: 'notify', size: HomeCardSize.s1x1),
  HomeCardLayout(id: 'mail', size: HomeCardSize.s1x1),
];

/// 一张卡在网格中的落位（像素坐标，相对网格左上角）。
@immutable
class PlacedHomeCard {
  const PlacedHomeCard({
    required this.id,
    required this.index,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.rows,
    required this.cols,
  });

  final String id;
  final int index;
  final double left;
  final double top;
  final double width;
  final double height;
  final int rows;
  final int cols;

  Rect get rect => Rect.fromLTWH(left, top, width, height);
}

@immutable
class HomePackResult {
  const HomePackResult({
    required this.cards,
    required this.unit,
    required this.totalHeight,
  });

  final List<PlacedHomeCard> cards;
  final double unit;
  final double totalHeight;
}

/// 纯函数：按顺序 first-fit 打包卡片到固定列数的方形单元网格。
///
/// [columns] 默认 4；[gap] 单元间距。返回每张卡的像素落位与整块总高，供
/// `_HomeGrid` 渲染与单元测试共用。
HomePackResult packHomeCards(
  List<HomeCardLayout> cards,
  double maxWidth, {
  double gap = 12,
  int columns = 4,
}) {
  final safeColumns = columns <= 0 ? 1 : columns;
  final unit = maxWidth <= 0
      ? 0.0
      : (maxWidth - gap * (safeColumns - 1)) / safeColumns;
  final occupied = <List<bool>>[];

  void ensureRows(int count) {
    while (occupied.length < count) {
      occupied.add(List<bool>.filled(safeColumns, false));
    }
  }

  bool canPlace(int row, int col, int rows, int cols) {
    if (col + cols > safeColumns) return false;
    ensureRows(row + rows);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        if (occupied[row + i][col + j]) return false;
      }
    }
    return true;
  }

  void fill(int row, int col, int rows, int cols) {
    ensureRows(row + rows);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        occupied[row + i][col + j] = true;
      }
    }
  }

  final placed = <PlacedHomeCard>[];
  var totalHeight = 0.0;

  for (var index = 0; index < cards.length; index++) {
    final card = cards[index];
    final span = spanOf(card.size);
    final rows = span.$1;
    final cols = span.$2;

    int? bestRow;
    var bestCol = 0;
    for (var row = 0; bestRow == null; row++) {
      if (row > occupied.length + rows) break;
      for (var col = 0; col + cols <= safeColumns; col++) {
        if (canPlace(row, col, rows, cols)) {
          bestRow = row;
          bestCol = col;
          break;
        }
      }
    }

    final row = bestRow ?? occupied.length;
    final col = bestCol;
    fill(row, col, rows, cols);

    final left = col * unit + col * gap;
    final top = row * unit + row * gap;
    final width = cols * unit + (cols - 1) * gap;
    final height = rows * unit + (rows - 1) * gap;

    placed.add(
      PlacedHomeCard(
        id: card.id,
        index: index,
        left: left,
        top: top,
        width: width,
        height: height,
        rows: rows,
        cols: cols,
      ),
    );
    if (top + height > totalHeight) totalHeight = top + height;
  }

  return HomePackResult(cards: placed, unit: unit, totalHeight: totalHeight);
}
