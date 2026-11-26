import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../common/care_widgets.dart';

/// 设置 → 主动关怀: briefings, quiet hours, idle sleep, calendar & notice access (M2).
class CareProactivePage extends ConsumerStatefulWidget {
  const CareProactivePage({super.key});

  @override
  ConsumerState<CareProactivePage> createState() => _CareProactivePageState();
}

class _CareProactivePageState extends ConsumerState<CareProactivePage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(careEcosystemProvider.notifier).refresh();
    }
  }

  Future<void> _update(CareBriefingConfig next) async {
    try {
      await ref.read(careScheduleProvider.notifier).updateConfig(next);
    } catch (_) {
      if (mounted) showCareSnack(context, '保存失败，请稍后再试。');
    }
  }

  Future<String?> _pickTime(String current, {String? helpText}) async {
    final t = await showTimePicker(
      context: context,
      initialTime: careParseHHmm(current),
      helpText: helpText,
    );
    return t == null ? null : careFormatHHmm(t);
  }

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(careScheduleProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('主动关怀')),
      body: schedule.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton(
            onPressed: () => ref.invalidate(careScheduleProvider),
            child: const Text('重试'),
          ),
        ),
        data: (s) {
          final c = s.config;
          return CareContentWidth(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                const CareSectionHeader('每日简报'),
                SwitchListTile(
                  secondary: const Icon(Icons.wb_sunny_outlined),
                  title: const Text('早间简报'),
                  subtitle: Text('每天 ${c.morningTime} 汇总今日日程与待办'),
                  value: c.morningEnabled,
                  onChanged: (v) => _update(c.copyWith(morningEnabled: v)),
                ),
                ListTile(
                  enabled: c.morningEnabled,
                  leading: const SizedBox(width: 24),
                  title: const Text('早间提醒时间'),
                  trailing: Text(c.morningTime),
                  onTap: () async {
                    final t = await _pickTime(
                      c.morningTime,
                      helpText: '选择早间简报时间',
                    );
                    if (t != null && mounted) {
                      await _update(c.copyWith(morningTime: t));
                    }
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.nights_stay_outlined),
                  title: const Text('晚间回顾'),
                  subtitle: Text('每天 ${c.eveningTime} 回顾今天、整理明天'),
                  value: c.eveningEnabled,
                  onChanged: (v) => _update(c.copyWith(eveningEnabled: v)),
                ),
                ListTile(
                  enabled: c.eveningEnabled,
                  leading: const SizedBox(width: 24),
                  title: const Text('晚间提醒时间'),
                  trailing: Text(c.eveningTime),
                  onTap: () async {
                    final t = await _pickTime(
                      c.eveningTime,
                      helpText: '选择晚间回顾时间',
                    );
                    if (t != null && mounted) {
                      await _update(c.copyWith(eveningTime: t));
                    }
                  },
                ),
                const CareSectionHeader('免打扰'),
                ListTile(
                  leading: const Icon(Icons.do_not_disturb_on_outlined),
                  title: const Text('免打扰时段'),
                  subtitle: const Text('这段时间内 Care 不会主动推送提醒'),
                  trailing: Text('${c.quietStart} – ${c.quietEnd}'),
                  onTap: () async {
                    final start = await _pickTime(
                      c.quietStart,
                      helpText: '选择免打扰开始时间',
                    );
                    if (start == null || !mounted) return;
                    final end = await _pickTime(
                      c.quietEnd,
                      helpText: '选择免打扰结束时间',
                    );
                    if (end == null || !mounted) return;
                    await _update(
                      c.copyWith(quietStart: start, quietEnd: end),
                    );
                  },
                ),
                const CareSectionHeader('省电'),
                ListTile(
                  leading: const Icon(Icons.energy_savings_leaf_outlined),
                  title: const Text('闲置后自动休眠'),
                  subtitle: const Text('离开 Care 一段时间后让它在后台休眠，到点会自动唤醒'),
                  trailing: DropdownButton<int>(
                    value: const [5, 15, 30, 60].contains(c.idleSleepMinutes)
                        ? c.idleSleepMinutes
                        : 15,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 5, child: Text('5 分钟')),
                      DropdownMenuItem(value: 15, child: Text('15 分钟')),
                      DropdownMenuItem(value: 30, child: Text('30 分钟')),
                      DropdownMenuItem(value: 60, child: Text('1 小时')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        _update(c.copyWith(idleSleepMinutes: v));
                      }
                    },
                  ),
                ),
                const CareSectionHeader('信息来源'),
                const _EcosystemTiles(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EcosystemTiles extends ConsumerWidget {
  const _EcosystemTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eco = ref.watch(careEcosystemProvider).value;
    final scheme = Theme.of(context).colorScheme;
    final calendarOn = eco?.calendarReadGranted ?? false;
    final noticeOn = eco?.noticeAccessEnabled ?? false;
    final allow = eco?.noticeAllowList ?? const <String>[];

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.calendar_month_outlined),
          title: const Text('系统日历'),
          subtitle: Text(calendarOn ? '已开启，简报会包含你的日程' : '未开启'),
          trailing: calendarOn
              ? Icon(Icons.check_rounded, color: scheme.primary)
              : TextButton(
                  onPressed: () async {
                    try {
                      await ref
                          .read(careEcosystemProvider.notifier)
                          .requestCalendarPermission();
                    } catch (_) {
                      if (context.mounted) showCareSnack(context, '无法申请日历权限。');
                    }
                  },
                  child: const Text('开启'),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('通知摘要'),
          subtitle: Text(
            noticeOn
                ? '已开启 · 仅读取你允许的 ${allow.length} 个应用，验证码类通知会被自动忽略'
                : '允许后，Care 可以把快递、航班等通知整理进简报',
          ),
          trailing: TextButton(
            onPressed: () async {
              try {
                await ref
                    .read(careEcosystemProvider.notifier)
                    .openNoticeAccessSettings();
              } catch (_) {
                if (context.mounted) showCareSnack(context, '无法打开系统设置。');
              }
            },
            child: Text(noticeOn ? '管理' : '去开启'),
          ),
        ),
        if (noticeOn)
          ListTile(
            leading: const SizedBox(width: 24),
            title: const Text('允许读取的应用'),
            subtitle: Text(
              allow.isEmpty ? '尚未选择任何应用' : allow.join('、'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => _AllowListDialog(initial: allow),
            ),
          ),
      ],
    );
  }
}

class _AllowListDialog extends ConsumerStatefulWidget {
  const _AllowListDialog({required this.initial});

  final List<String> initial;

  @override
  ConsumerState<_AllowListDialog> createState() => _AllowListDialogState();
}

class _AllowListDialogState extends ConsumerState<_AllowListDialog> {
  static const _presets = <(String, String)>[
    ('菜鸟', 'com.cainiao.wireless'),
    ('顺丰', 'com.sf.activity'),
    ('航旅纵横', 'com.umetrip.android.msky.app'),
    ('铁路 12306', 'com.MobileTicket'),
    ('微信', 'com.tencent.mm'),
    ('钉钉', 'com.alibaba.android.rimet'),
    ('飞书', 'com.ss.android.lark'),
  ];

  late final _ctrl = TextEditingController(text: widget.initial.join('\n'));
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<String> _parseList() => _ctrl.text
      .split(RegExp(r'[\s,，、]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  void _togglePreset(String pkg) {
    final list = _parseList();
    if (list.contains(pkg)) {
      list.remove(pkg);
    } else {
      list.add(pkg);
    }
    setState(() => _ctrl.text = list.join('\n'));
  }

  Future<void> _save() async {
    final list = _parseList();
    setState(() => _busy = true);
    try {
      await ref.read(careEcosystemProvider.notifier).setNoticeAllowList(list);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showCareSnack(context, '保存失败，请稍后再试。');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _parseList().toSet();
    return AlertDialog(
      title: const Text('允许读取的应用'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('点击下方常用应用快速勾选，或手动补充应用包名。验证码类通知始终会被自动忽略。'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (label, pkg) in _presets)
                  FilterChip(
                    label: Text(label),
                    selected: current.contains(pkg),
                    shape: const StadiumBorder(),
                    onSelected: _busy ? null : (_) => _togglePreset(pkg),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              enabled: !_busy,
              minLines: 3,
              maxLines: 6,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                labelText: '应用包名（每行一个）',
                hintText: 'com.example.express',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: _busy ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
