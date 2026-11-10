/// Room-code building table from the 后勤处缴费编号 page
/// (hqglc.neu.edu.cn 2024-07-02 revision, verified against live queries:
/// 3510409 → 浑南校区5舍A区0409寝室, 2600116 → 南湖六舍西0116寝室).
///
/// 电费房间码 = 楼栋缴费编号(3位, 空调楼 4位) + 寝室号(4位, 不足补 0)。
library;

class DormBuilding {
  const DormBuilding({required this.code, required this.label});

  /// 缴费编号前缀 (3位，空调楼为4位)。
  final String code;

  /// 展示名，如「浑南 一舍A」。
  final String label;
}

const dormCampusNames = <String, List<DormBuilding>>{
  '南湖校区': [
    DormBuilding(code: '211', label: '一舍（东）'),
    DormBuilding(code: '212', label: '一舍（南）'),
    DormBuilding(code: '213', label: '一舍（西）'),
    DormBuilding(code: '221', label: '二舍'),
    DormBuilding(code: '222', label: '二舍'),
    DormBuilding(code: '223', label: '二舍'),
    DormBuilding(code: '521', label: '新二舍A'),
    DormBuilding(code: '621', label: '新二舍A 空调'),
    DormBuilding(code: '522', label: '新二舍B'),
    DormBuilding(code: '622', label: '新二舍B 空调'),
    DormBuilding(code: '131', label: '三舍'),
    DormBuilding(code: '132', label: '三舍'),
    DormBuilding(code: '133', label: '三舍'),
    DormBuilding(code: '140', label: '四舍'),
    DormBuilding(code: '150', label: '五舍'),
    DormBuilding(code: '260', label: '六舍（西）'),
    DormBuilding(code: '170', label: '七舍'),
    DormBuilding(code: '181', label: '八舍 1 单元'),
    DormBuilding(code: '182', label: '八舍 2 单元'),
    DormBuilding(code: '183', label: '八舍 3 单元'),
    DormBuilding(code: '184', label: '八舍 4 单元'),
    DormBuilding(code: '185', label: '八舍 5 单元'),
    DormBuilding(code: '186', label: '八舍 6 单元'),
    DormBuilding(code: '187', label: '八舍 7 单元'),
    DormBuilding(code: '188', label: '八舍 8 单元'),
    DormBuilding(code: '191', label: '九舍 1 单元'),
    DormBuilding(code: '192', label: '九舍 2 单元'),
    DormBuilding(code: '193', label: '九舍 3 单元'),
    DormBuilding(code: '194', label: '九舍 4 单元'),
    DormBuilding(code: '195', label: '九舍 5 单元'),
    DormBuilding(code: '196', label: '九舍 6 单元'),
    DormBuilding(code: '197', label: '九舍 7 单元'),
    DormBuilding(code: '291', label: '九舍 空调 1'),
    DormBuilding(code: '292', label: '九舍 空调 2'),
    DormBuilding(code: '293', label: '九舍 空调 3'),
    DormBuilding(code: '294', label: '九舍 空调 4'),
    DormBuilding(code: '295', label: '九舍 空调 5'),
    DormBuilding(code: '296', label: '九舍 空调 6'),
    DormBuilding(code: '297', label: '九舍 空调 7'),
    DormBuilding(code: '111', label: '十舍'),
    DormBuilding(code: '112', label: '十舍'),
    DormBuilding(code: '113', label: '十舍'),
    DormBuilding(code: '121', label: '博士后公寓'),
    DormBuilding(code: '122', label: '博士后公寓'),
    DormBuilding(code: '123', label: '软件公寓'),
    DormBuilding(code: '230', label: '后勤公寓'),
    DormBuilding(code: '270', label: '培训公寓'),
    DormBuilding(code: '420', label: '留学生公寓'),
    DormBuilding(code: '430', label: '留学生公寓'),
    DormBuilding(code: '440', label: '留学生公寓'),
  ],
  '浑南校区': [
    DormBuilding(code: '311', label: '一舍A'),
    DormBuilding(code: '3111', label: '一舍A 空调'),
    DormBuilding(code: '312', label: '一舍B'),
    DormBuilding(code: '3122', label: '一舍B 空调'),
    DormBuilding(code: '321', label: '二舍A'),
    DormBuilding(code: '3211', label: '二舍A 空调'),
    DormBuilding(code: '322', label: '二舍B'),
    DormBuilding(code: '3222', label: '二舍B 空调'),
    DormBuilding(code: '331', label: '三舍A'),
    DormBuilding(code: '3311', label: '三舍A 空调'),
    DormBuilding(code: '332', label: '三舍B'),
    DormBuilding(code: '3322', label: '三舍B 空调'),
    DormBuilding(code: '341', label: '四舍'),
    DormBuilding(code: '342', label: '四舍'),
    DormBuilding(code: '351', label: '五舍A'),
    DormBuilding(code: '352', label: '五舍B'),
  ],
};

/// 楼栋编号 + 寝室号 → 7/8 位房间码。寝室号不足 4 位左侧补 0。
String buildRoomCode(String buildingCode, String roomNumber) {
  final digits = roomNumber.replaceAll(RegExp(r'\D'), '');
  final padded = digits.padLeft(4, '0');
  return '$buildingCode$padded';
}

class ElectricityReading {
  const ElectricityReading({
    required this.roomCode,
    required this.roomInfo,
    required this.remainKwh,
    required this.rawRemain,
    this.meterAddr,
    this.lastReadTime,
    required this.fetchedAt,
  });

  final String roomCode;
  final String roomInfo;
  final double remainKwh;
  final String rawRemain;
  final String? meterAddr;
  final DateTime? lastReadTime;
  final DateTime fetchedAt;

  static DateTime? _parseSlashDate(String? raw) {
    if (raw == null) return null;
    final match =
        RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})\s+(\d{1,2}):(\d{2}):(\d{2})')
            .firstMatch(raw.trim());
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  factory ElectricityReading.fromJson(Map<String, dynamic> json) {
    return ElectricityReading(
      roomCode: json['roomCode'] as String? ?? '',
      roomInfo: json['roomInfo'] as String? ?? '',
      remainKwh: (json['remainKwh'] as num?)?.toDouble() ?? 0,
      rawRemain: json['rawRemain'] as String? ?? '',
      meterAddr: json['meterAddr'] as String?,
      lastReadTime: DateTime.tryParse(json['lastReadTime'] as String? ?? ''),
      fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'roomCode': roomCode,
        'roomInfo': roomInfo,
        'remainKwh': remainKwh,
        'rawRemain': rawRemain,
        if (meterAddr != null) 'meterAddr': meterAddr,
        if (lastReadTime != null) 'lastReadTime': lastReadTime!.toIso8601String(),
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory ElectricityReading.fromPayResponse({
    required String roomCode,
    required Map<String, dynamic> json,
  }) {
    final rawRemain = (json['elecRemain'] as String? ?? '').trim();
    final number = RegExp(r'[\d.]+').firstMatch(rawRemain)?.group(0);
    return ElectricityReading(
      roomCode: roomCode,
      roomInfo: (json['elecroominfo'] as String? ?? '').trim(),
      remainKwh: number == null ? 0 : double.tryParse(number) ?? 0,
      rawRemain: rawRemain,
      meterAddr: json['mAddr'] as String?,
      lastReadTime: _parseSlashDate(json['lastReadTime'] as String?),
      fetchedAt: DateTime.now(),
    );
  }
}

/// 本地保存的寝室用电偏好与最近一次查询结果。
class DormPrefs {
  const DormPrefs({
    this.roomCode,
    this.alertThreshold = 20,
    this.lastQueryDate,
    this.lastReading,
  });

  final String? roomCode;
  final double alertThreshold;
  final DateTime? lastQueryDate;
  final ElectricityReading? lastReading;

  bool get hasRoom => roomCode != null && roomCode!.trim().isNotEmpty;

  factory DormPrefs.fromJson(Map<String, dynamic> json) {
    final threshold = (json['alertThreshold'] as num?)?.toDouble();
    return DormPrefs(
      roomCode: json['roomCode'] as String?,
      alertThreshold: threshold == null || threshold <= 0 ? 20 : threshold,
      lastQueryDate: DateTime.tryParse(json['lastQueryDate'] as String? ?? ''),
      lastReading: json['lastReading'] is Map
          ? ElectricityReading.fromJson(
              Map<String, dynamic>.from(json['lastReading'] as Map),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (roomCode != null) 'roomCode': roomCode,
        'alertThreshold': alertThreshold,
        if (lastQueryDate != null)
          'lastQueryDate': DateTime(
            lastQueryDate!.year,
            lastQueryDate!.month,
            lastQueryDate!.day,
          ).toIso8601String(),
        if (lastReading != null) 'lastReading': lastReading!.toJson(),
      };
}
