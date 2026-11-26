import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../automation/care_automation_page.dart';
import '../care_theme.dart';
import '../common/care_copy.dart';
import '../common/care_markdown_view.dart';
import '../common/care_widgets.dart';
import '../settings/care_proactive_page.dart';

/// 「今日」hub: morning/evening briefings, life reminders, quick routines,
/// upcoming calendar events and the whitelisted notification digest (M2/M3).
class CareTodayPage extends ConsumerWidget {
  const CareTodayPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    await Future.wait([
      ref.read(careScheduleProvider.notifier).refreshReminders(),
      ref.read(careEcosystemProvider.notifier).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final theme = Theme.of(context);

    return CareAtmosphereBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('今日'),
          actions: [
            IconButton(
              tooltip: '主动关怀设置',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CareProactivePage(),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: CareContentWidth(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                Text(
                  careGreeting(now),
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  careDateLabel(now),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                const _BriefingCard(),
                const _SectionTitle(title: '提醒', trailing: _AddReminderButton()),
                const _RemindersList(),
                const _QuickRoutinesSection(),
                const _SectionTitle(title: '近 7 天日程', trailing: _AddEventButton()),
                const _CalendarSection(),
                const _NoticesSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ───────────────────────────── Briefing ─────────────────────────────

class _BriefingCard extends ConsumerWidget {
  const _BriefingCard();

  Future<void> _generate(
    BuildContext context,
    WidgetRef ref,
    CareBriefingKind kind,
  ) async {
    try {
      await ref
          .read(careScheduleProvider.notifier)
          .generateBriefingNow(kind, notify: false);
    } catch (_) {
      if (context.mounted) showCareSnack(context, '简报生成失败，请稍后再试。');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(careScheduleProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = schedule.value;
    final briefing = s?.latestBriefing;
    final generating = s?.isGeneratingBriefing ?? false;
    final morning = DateTime.now().hour < 15;

    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  morning ? Icons.wb_sunny_outlined : Icons.nights_stay_outlined,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    briefing?.title ?? (morning ? '早间简报' : '晚间回顾'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (briefing != null)
                  Text(
                    careRelativeTime(briefing.generatedAt),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (schedule.isLoading && s == null)
              const LinearProgressIndicator()
            else if (briefing != null)
              CareMarkdownView(
                markdown: _stripTitle(briefing.summaryMarkdown),
                baseStyle: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
              )
            else
              Text(
                '按需汇总今日日程、提醒与通知。',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: generating || s == null
                      ? null
                      : () => _generate(context, ref, CareBriefingKind.morning),
                  icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                  label: const Text('早间简报'),
                ),
                FilledButton.tonalIcon(
                  onPressed: generating || s == null
                      ? null
                      : () => _generate(context, ref, CareBriefingKind.evening),
                  icon: const Icon(Icons.nights_stay_outlined, size: 18),
                  label: const Text('晚间回顾'),
                ),
                if (briefing != null)
                  OutlinedButton.icon(
                    onPressed: generating
                        ? null
                        : () {
                            final prompt =
                                '请结合我刚刚生成的「${briefing.title}」，帮我梳理今天最重要的 3 件事和下一步建议：\n\n${briefing.summaryMarkdown}';
                            ref.read(careChatProvider.notifier).sendMessage(prompt);
                            Navigator.of(context).pop();
                          },
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                    label: const Text('聊聊这份简报'),
                  ),
                if (generating)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _stripTitle(String md) {
    final lines = md.split('\n');
    if (lines.isNotEmpty && lines.first.startsWith('# ')) {
      return lines.skip(1).join('\n').trim();
    }
    return md;
  }
}

// ───────────────────────────── Reminders ─────────────────────────────

class _AddReminderButton extends ConsumerWidget {
  const _AddReminderButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => const CareReminderDialog(),
      ),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('添加'),
    );
  }
}

class _RemindersList extends ConsumerStatefulWidget {
  const _RemindersList();

  @override
  ConsumerState<_RemindersList> createState() => _RemindersListState();
}

class _RemindersListState extends ConsumerState<_RemindersList> {
  bool _showCompleted = false;

  Future<void> _guard(BuildContext context, Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {
      if (context.mounted) showCareSnack(context, '操作失败，请稍后再试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(careScheduleProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return schedule.when(
      skipLoadingOnReload: true,
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const CareHintCard(
        icon: Icons.error_outline_rounded,
        title: '暂时无法读取提醒',
        body: '下拉页面可以重新加载。',
      ),
      data: (s) {
        final active = [...s.activeReminders]
          ..sort((a, b) => a.triggerAt.compareTo(b.triggerAt));
        final done = s.reminders.where((r) => r.done).toList()
          ..sort((a, b) => b.triggerAt.compareTo(a.triggerAt));
        if (active.isEmpty && done.isEmpty) {
          return const CareHintCard(
            icon: Icons.notifications_none_rounded,
            title: '暂时没有提醒',
            body: '点击「添加」，或者直接在聊天里说「两周后提醒我买猫粮」。',
          );
        }
        return Card(
          child: Column(
            children: [
              if (active.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          size: 20, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '当前提醒都已完成，真棒！',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              for (final r in active)
                ListTile(
                  key: ValueKey(r.id),
                  leading: IconButton(
                    tooltip: '标记完成',
                    icon: Icon(Icons.radio_button_unchecked_rounded,
                        color: scheme.primary),
                    onPressed: () => _guard(
                      context,
                      () => ref
                          .read(careScheduleProvider.notifier)
                          .markReminderDone(r.id),
                    ),
                  ),
                  title: Text(r.title),
                  subtitle: Text(
                    [
                      careRelativeTime(r.triggerAt),
                      if (r.repeatDays > 0) careRepeatLabel(r.repeatDays),
                      if (r.body.isNotEmpty) r.body,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _guard(
                      context,
                      () => ref
                          .read(careScheduleProvider.notifier)
                          .cancelReminder(r.id),
                    ),
                  ),
                ),
              if (done.isNotEmpty) ...[
                if (active.isNotEmpty) const Divider(indent: 20, endIndent: 20),
                InkWell(
                  onTap: () => setState(() => _showCompleted = !_showCompleted),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '已完成（${done.length}）',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const Spacer(),
                        Icon(
                          _showCompleted
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showCompleted)
                  for (final r in done.take(8))
                    ListTile(
                      key: ValueKey('done-${r.id}'),
                      dense: true,
                      leading: Icon(Icons.check_circle_rounded,
                          size: 20, color: scheme.primary.withValues(alpha: 0.7)),
                      title: Text(
                        r.title,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      subtitle: Text(careRelativeTime(r.triggerAt)),
                    ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class CareReminderDialog extends ConsumerStatefulWidget {
  const CareReminderDialog({super.key});

  @override
  ConsumerState<CareReminderDialog> createState() => _CareReminderDialogState();
}

class _CareReminderDialogState extends ConsumerState<CareReminderDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late DateTime _at;
  int _repeat = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now().add(const Duration(hours: 1));
    _at = DateTime(n.year, n.month, n.day, n.hour);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (d != null) {
      setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (t != null) {
      setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '请写下要提醒的事情');
      return;
    }
    if (_at.isBefore(DateTime.now())) {
      setState(() => _error = '提醒时间需要晚于现在');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(careScheduleProvider.notifier).addReminder(
            title: _title.text,
            body: _body.text,
            triggerAt: _at,
            repeatDays: _repeat,
          );
      if (mounted) {
        Navigator.of(context).pop();
        showCareSnack(context, '好的，${careRelativeTime(_at)} 提醒你');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '设置提醒失败，请稍后再试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新提醒'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              enabled: !_busy,
              decoration: InputDecoration(
                hintText: '要提醒什么？',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              enabled: !_busy,
              decoration: const InputDecoration(hintText: '备注（可选）'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickDate,
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text('${_at.month}月${_at.day}日'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickTime,
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text(careClockTime(_at)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _repeat,
              decoration: const InputDecoration(labelText: '重复'),
              items: [
                for (final d in const [0, 1, 7, 14, 30])
                  DropdownMenuItem(value: d, child: Text(careRepeatLabel(d))),
              ],
              onChanged: _busy ? null : (v) => setState(() => _repeat = v ?? 0),
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

// ───────────────────────────── Quick Routines ─────────────────────────────

class _ManageRoutinesButton extends StatelessWidget {
  const _ManageRoutinesButton();

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const CareAutomationPage()),
      ),
      icon: const Icon(Icons.auto_awesome_outlined, size: 17),
      label: const Text('管理'),
    );
  }
}

class _QuickRoutinesSection extends ConsumerWidget {
  const _QuickRoutinesSection();

  Future<void> _run(BuildContext context, WidgetRef ref, CareRoutine r) async {
    try {
      final result = await ref.read(careRoutineProvider.notifier).runRoutine(r.id);
      if (!context.mounted) return;
      showCareSnack(
        context,
        result.pausedForApproval
            ? '「${r.name}」已暂停，正在等待你确认'
            : result.completed
                ? '「${r.name}」已完成：${result.summary}'
                : result.summary,
      );
    } catch (_) {
      if (context.mounted) showCareSnack(context, '运行失败，请稍后再试。');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(careRoutineProvider);
    final scheme = Theme.of(context).colorScheme;

    return routines.when(
      skipLoadingOnReload: true,
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (s) {
        if (s.routines.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              title: '定时任务',
              trailing: _ManageRoutinesButton(),
            ),
            Card(
              child: Column(
                children: [
                  for (final r in s.routines.take(3))
                    ListTile(
                      key: ValueKey('today-rt-${r.id}'),
                      leading: Icon(
                        Icons.schedule_rounded,
                        color: scheme.primary,
                      ),
                      title: Text(r.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        r.scheduleTimeHHmm != null
                            ? '${r.steps.length} 个步骤 · 每天 ${r.scheduleTimeHHmm}'
                            : '${r.steps.length} 个步骤 · 手动运行',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: s.runningRoutineId == r.id
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(56, 36),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                              ),
                              onPressed: s.runningRoutineId != null
                                  ? null
                                  : () => _run(context, ref, r),
                              child: const Text('运行'),
                            ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ───────────────────────────── Calendar ─────────────────────────────

class _AddEventButton extends ConsumerWidget {
  const _AddEventButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite = ref.watch(
      careEcosystemProvider.select((s) => s.value?.calendarWriteGranted ?? false),
    );
    if (!canWrite) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => const _EventDialog(),
      ),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('添加'),
    );
  }
}

class _CalendarSection extends ConsumerWidget {
  const _CalendarSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eco = ref.watch(careEcosystemProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return eco.when(
      skipLoadingOnReload: true,
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const CareHintCard(
        icon: Icons.error_outline_rounded,
        title: '暂时无法读取日历',
        body: '下拉页面可以重新加载。',
      ),
      data: (s) {
        if (!s.calendarReadGranted) {
          return CareHintCard(
            icon: Icons.calendar_month_outlined,
            title: '让 Care 看看你的日程',
            body: '开启日历权限后，Care 可以在简报里提醒你今天的安排，也能帮你添加日程。不开启也不影响聊天。',
            action: FilledButton.tonal(
              onPressed: () async {
                try {
                  final ok = await ref
                      .read(careEcosystemProvider.notifier)
                      .requestCalendarPermission();
                  if (!ok && context.mounted) {
                    showCareSnack(context, '没有获得日历权限，你可以稍后在系统设置中开启。');
                  }
                } catch (_) {
                  if (context.mounted) showCareSnack(context, '无法申请日历权限。');
                }
              },
              child: const Text('开启日历'),
            ),
          );
        }
        if (s.upcomingEvents.isEmpty) {
          return const CareHintCard(
            icon: Icons.event_available_outlined,
            title: '近期没有安排',
            body: '接下来 7 天都很空闲。',
          );
        }
        final events = [...s.upcomingEvents]
          ..sort((a, b) => a.start.compareTo(b.start));
        return Card(
          child: Column(
            children: [
              for (final e in events.take(10))
                ListTile(
                  key: ValueKey(e.id),
                  leading: Container(
                    width: 44,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${e.start.month}月',
                            style: theme.textTheme.labelSmall),
                        Text(
                          '${e.start.day}',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  title: Text(e.title),
                  subtitle: Text(
                    [
                      e.allDay
                          ? '全天'
                          : '${careClockTime(e.start)} – ${careClockTime(e.end)}',
                      if (e.location.isNotEmpty) e.location,
                    ].join(' · '),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EventDialog extends ConsumerStatefulWidget {
  const _EventDialog();

  @override
  ConsumerState<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends ConsumerState<_EventDialog> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  late DateTime _start;
  int _minutes = 60;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now().add(const Duration(hours: 1));
    _start = DateTime(n.year, n.month, n.day, n.hour);
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (t == null) return;
    setState(() => _start = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '请填写日程标题');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await ref.read(careEcosystemProvider.notifier).createCalendarEvent(
            title: _title.text,
            start: _start,
            end: _start.add(Duration(minutes: _minutes)),
            location: _location.text.trim().isEmpty ? null : _location.text.trim(),
          );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
        showCareSnack(context, '已添加到系统日历');
      } else {
        setState(() {
          _busy = false;
          _error = '没能添加日程，请检查日历权限';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '没能添加日程，请稍后再试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加日程'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              enabled: !_busy,
              decoration: InputDecoration(hintText: '日程标题', errorText: _error),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _location,
              enabled: !_busy,
              decoration: const InputDecoration(hintText: '地点（可选）'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(careRelativeTime(_start)),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _minutes,
              decoration: const InputDecoration(labelText: '时长'),
              items: const [
                DropdownMenuItem(value: 30, child: Text('30 分钟')),
                DropdownMenuItem(value: 60, child: Text('1 小时')),
                DropdownMenuItem(value: 120, child: Text('2 小时')),
                DropdownMenuItem(value: 240, child: Text('半天')),
              ],
              onChanged: _busy ? null : (v) => setState(() => _minutes = v ?? 60),
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
          child: const Text('添加'),
        ),
      ],
    );
  }
}

// ───────────────────────────── Notices ─────────────────────────────

class _NoticesSection extends ConsumerWidget {
  const _NoticesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eco = ref.watch(careEcosystemProvider).value;
    if (eco == null) return const SizedBox.shrink();
    final notices = eco.recentNotices;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: '通知摘要',
          trailing: notices.isNotEmpty
              ? TextButton(
                  onPressed: () async {
                    try {
                      await ref.read(careEcosystemProvider.notifier).clearNotices();
                    } catch (_) {
                      if (context.mounted) showCareSnack(context, '清除失败，请稍后再试。');
                    }
                  },
                  child: const Text('清除'),
                )
              : null,
        ),
        if (!eco.noticeAccessEnabled)
          CareHintCard(
            icon: Icons.notifications_active_outlined,
            title: '整理快递与出行通知',
            body: '按需开启后，Care 只读取你选定的应用通知并自动忽略验证码，整理进早晚简报。',
            action: FilledButton.tonal(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CareProactivePage(),
                ),
              ),
              child: const Text('去设置'),
            ),
          )
        else if (notices.isEmpty)
          const CareHintCard(
            icon: Icons.mark_chat_read_outlined,
            title: '暂无新通知摘要',
            body: '已开启白名单通知读取，验证码与敏感短信会自动忽略。',
          )
        else
          Card(
            child: Column(
              children: [
                for (final n in notices.take(6))
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(n.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Text(
                      careClockTime(n.postedAt),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
