part of '../dorm_page.dart';

extension _DormPowerCards on _DormPowerPageState {
  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '寝室用电',
          style: TextStyle(
            fontSize: _compact ? 21 : 24,
            height: 1.2,
            letterSpacing: -0.3,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _prefs.hasRoom
              ? (_prefs.lastReading?.roomInfo.isNotEmpty ?? false)
                    ? _prefs.lastReading!.roomInfo
                    : '已保存房间码 ${_prefs.roomCode}'
              : '填写一次房间码，之后打开即可查看剩余电量',
          style: TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ],
    );
  }

  // ---------- setup ----------

  Widget _buildSetupCard() {
    final buildings = dormCampusNames[_campus]!;
    final preview = _buildingCode == null || _roomController.text.isEmpty
        ? null
        : buildRoomCode(_buildingCode!, _roomController.text);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _fullCodeController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 8,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: _fieldDecoration('完整房间码（7/8 位，自动识别楼栋与寝室）')
                .copyWith(counterText: ''),
            onChanged: _onFullCodeChanged,
          ),
          const SizedBox(height: 14),
          Text('选择楼栋', style: _cardTitleStyle()),
          const SizedBox(height: 10),
          _campusSegmented(),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('building-$_campus-${_buildingCode ?? ''}'),
            initialValue: _buildingCode,
            isDense: true,
            decoration: _fieldDecoration('楼栋（缴费编号）'),
            items: [
              for (final building in buildings)
                DropdownMenuItem(
                  value: building.code,
                  child: Text(
                    '${building.label} · ${building.code}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
            onChanged: (value) => _rebuild(() {
              _buildingCode = value;
              _syncFullCodeFromParts();
            }),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _roomController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 4,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: _fieldDecoration('寝室号（4 位，不足自动补 0）')
                .copyWith(counterText: ''),
            onChanged: (_) => _rebuild(_syncFullCodeFromParts),
          ),
          if (preview != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.campusBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '房间码 $preview',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.campusBlue,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _thresholdController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: _fieldDecoration('剩余多少度时提醒（默认 20）'),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.campusBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
                ),
                onPressed: _loading
                    ? null
                    : () => _saveAndQuery(
                        roomCode: _fullCodeController.text.trim().isNotEmpty
                            ? _fullCodeController.text.trim()
                            : (preview ?? ''),
                      ),
                child: _loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('保存并查询'),
              ),
            ],
          ),
          if (_prefs.hasRoom) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _rebuild(() => _editing = false),
              child: const Text('取消修改'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _campusSegmented() {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          for (final campus in dormCampusNames.keys)
            Expanded(
              child: GestureDetector(
                onTap: () => _rebuild(() {
                  _campus = campus;
                  _buildingCode = null;
                  _fullCodeController.clear();
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _campus == campus
                        ? AppColors.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: _campus == campus
                        ? Border.all(color: AppColors.line)
                        : null,
                  ),
                  child: Text(
                    campus,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: _campus == campus
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: _campus == campus
                          ? AppColors.ink
                          : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- reading ----------

  Widget _buildReadingCard(ElectricityReading reading) {
    final low = _isLow;
    final accent = low ? AppColors.nowRed : AppColors.campusBlue;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reading.roomInfo.isEmpty
                      ? '房间码 ${reading.roomCode}'
                      : reading.roomInfo,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _testNotification,
                icon: const Icon(Icons.notifications_active_outlined, size: 14),
                label: const Text('测试通知'),
              ),
              TextButton(
                onPressed: () => _rebuild(() => _editing = true),
                child: const Text('修改房间'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                reading.remainKwh == reading.remainKwh.truncateToDouble()
                    ? reading.remainKwh.truncate().toString()
                    : reading.remainKwh.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 44,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: accent,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              Text('度', style: TextStyle(fontSize: 14, color: AppColors.muted)),
              const Spacer(),
              TextButton.icon(
                onPressed: _loading ? null : _refresh,
                icon: _loading
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('立即刷新'),
              ),
            ],
          ),
          if (low) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.nowRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '剩余电量已低于提醒线（${_prefs.alertThreshold.truncate()} 度），建议尽快充值。',
                style: TextStyle(fontSize: 11, color: AppColors.nowRed),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.line),
          const SizedBox(height: 10),
          _metaRow('电表读数时间', reading.lastReadTime),
          _metaRow('本次查询时间', reading.fetchedAt),
          if (reading.meterAddr != null && reading.meterAddr!.isNotEmpty)
            _metaRow('电表地址', null, value: reading.meterAddr),
        ],
      ),
    );
  }

  Widget _buildEmptyReadingCard() {
    return _card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Icon(Icons.bolt_outlined, size: 28, color: AppColors.faint),
            const SizedBox(height: 8),
            Text(
              '房间码已保存，点击「立即刷新」查询剩余电量',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.campusBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 36),
              ),
              onPressed: _loading ? null : _refresh,
              child: _loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('立即查询'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdCard() {
    return _card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('提醒线', style: _cardTitleStyle()),
                const SizedBox(height: 4),
                Text(
                  '剩余电量低于提醒线时，打开软件会弹窗与系统通知提醒',
                  style: TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _Stepper36(
            value: _prefs.alertThreshold.truncate(),
            unit: '度',
            onChanged: (value) => _updateThreshold(value.toDouble()),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 11, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- shared bits ----------

  TextStyle _cardTitleStyle() => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 11, color: AppColors.muted),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.campusBlue),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }

  Widget _metaRow(String label, DateTime? time, {String? value}) {
    final shown =
        value ??
        (time == null
            ? '—'
            : '${time.year}/${time.month}/${time.day} '
                  '${time.hour}:${time.minute.toString().padLeft(2, '0')}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(fontSize: 10, color: AppColors.faint),
            ),
          ),
          Expanded(
            child: Text(
              shown,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.ink.withValues(alpha: 0.85),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stepper36 extends StatelessWidget {
  const _Stepper36({
    required this.value,
    required this.unit,
    required this.onChanged,
  });

  final int value;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _step(Icons.remove, () => onChanged(value > 5 ? value - 5 : 5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$value $unit',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _step(Icons.add, () => onChanged(value + 5)),
        ],
      ),
    );
  }

  Widget _step(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 15, color: AppColors.muted),
      ),
    );
  }
}
