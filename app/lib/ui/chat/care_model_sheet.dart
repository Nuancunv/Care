import 'package:care_app/services/care_deepseek_direct.dart';
import 'package:care_app/state/care_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../common/care_copy.dart';
import '../common/care_widgets.dart';

/// Bottom sheet letting the user independently configure the active Bot's
/// DeepSeek model (including live-discovered `/v1/models` & custom future models)
/// and thinking effort (`none` / `low` / `high` / `max`).
Future<void> showCareModelEffortSheet(
  BuildContext context, {
  required CareBotProfile bot,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _CareModelEffortSheet(bot: bot),
  );
}

class _CareModelEffortSheet extends ConsumerStatefulWidget {
  const _CareModelEffortSheet({required this.bot});

  final CareBotProfile bot;

  @override
  ConsumerState<_CareModelEffortSheet> createState() =>
      _CareModelEffortSheetState();
}

class _CareModelEffortSheetState extends ConsumerState<_CareModelEffortSheet> {
  final _customModelCtrl = TextEditingController();
  late String _selectedModel;
  late String _selectedEffort;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(careSettingsProvider).value;
    _selectedModel = widget.bot.isChief
        ? (settings?.activeModel ?? widget.bot.preferredModel)
        : widget.bot.preferredModel;
    _selectedEffort = widget.bot.isChief
        ? (settings?.activeEffort ?? widget.bot.preferredEffort)
        : widget.bot.preferredEffort;
  }

  @override
  void dispose() {
    _customModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshLiveModels() async {
    setState(() => _refreshing = true);
    try {
      final ok = await ref
          .read(careSettingsProvider.notifier)
          .verifyDirectConnection();
      if (mounted) {
        showCareSnack(
          context,
          ok ? '已从接口拉取最新模型列表' : '拉取失败，请检查网络或 API Key',
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _apply({String? model, String? effort}) async {
    final nextModel = model ?? _selectedModel;
    final nextEffort = effort ?? _selectedEffort;
    setState(() {
      _selectedModel = nextModel;
      _selectedEffort = nextEffort;
    });
    await ref.read(careBotsProvider.notifier).updateBotConfig(
          widget.bot.id,
          preferredModel: nextModel,
          preferredEffort: nextEffort,
        );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(careSettingsProvider).value;
    final models = <String>{
      ...?settings?.availableModels
          .where((m) => !kCareLegacyModels.contains(m)),
      ...kCareDefaultModels,
      if (!kCareLegacyModels.contains(_selectedModel)) _selectedModel,
    }.toList();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.bot.name} · 模型与思考',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _refreshing ? null : _refreshLiveModels,
                    icon: _refreshing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('刷新最新模型'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '思考强度',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final e in kCareReasoningEfforts)
                    ButtonSegment<String>(
                      value: e,
                      label: Text(careEffortShortLabel(e)),
                    ),
                ],
                selected: {_selectedEffort},
                onSelectionChanged: (set) {
                  if (set.isNotEmpty) _apply(effort: set.first);
                },
              ),
              const SizedBox(height: 18),
              Text(
                '选择模型',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              RadioGroup<String>(
                groupValue: _selectedModel,
                onChanged: (v) {
                  if (v != null) _apply(model: v);
                },
                child: Column(
                  children: [
                    for (final m in models)
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: m,
                        title: Text(careModelLabel(m)),
                        subtitle: Text(
                          careModelDescription(m),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customModelCtrl,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        hintText: '手动指定新模型 ID（如 deepseek-v5）',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 44),
                    ),
                    onPressed: () {
                      final raw = _customModelCtrl.text.trim();
                      if (raw.isEmpty) return;
                      _customModelCtrl.clear();
                      _apply(model: raw);
                    },
                    child: const Text('使用'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
