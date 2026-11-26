import 'package:care_app/state/care_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../common/care_copy.dart';
import '../common/care_widgets.dart';

/// First-run BYOK onboarding: welcome → paste DeepSeek key → verify → done.
class CareOnboardingPage extends ConsumerStatefulWidget {
  const CareOnboardingPage({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  ConsumerState<CareOnboardingPage> createState() => _CareOnboardingPageState();
}

class _CareOnboardingPageState extends ConsumerState<CareOnboardingPage> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (_step) {
      0 => _WelcomeStep(
          key: const ValueKey(0),
          onNext: () => setState(() => _step = 1),
        ),
      1 => _ApiKeyStep(
          key: const ValueKey(1),
          onBack: () => setState(() => _step = 0),
          onVerified: () => setState(() => _step = 2),
          onSkip: widget.onFinished,
        ),
      _ => _ReadyStep(key: const ValueKey(2), onStart: widget.onFinished),
    };

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) setState(() => _step = 0);
      },
      child: Scaffold(
        body: SafeArea(
          child: CareContentWidth(
            maxWidth: 560,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  const CareAvatar(size: 64),
                  const SizedBox(height: 28),
                  Text(
                    '你好，我是 Care',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '住在你手机里的私人 Bot 团队。',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 40),
                  const _Feature(
                    icon: Icons.lock_outline_rounded,
                    title: '数据只留在你的手机',
                    body: '对话、记忆和性格设定都保存在本机，不经过任何中转服务器。',
                  ),
                  const _Feature(
                    icon: Icons.key_rounded,
                    title: '用你自己的 DeepSeek Key',
                    body: '直接连接 DeepSeek 官方服务，按实际用量付费，没有订阅。',
                  ),
                  const _Feature(
                    icon: Icons.edit_note_rounded,
                    title: '记忆透明，随时可改',
                    body: '我记住了什么、用什么语气和你说话，你都能看到并修改。',
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onNext, child: const Text('开始设置')),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiKeyStep extends ConsumerStatefulWidget {
  const _ApiKeyStep({
    super.key,
    required this.onBack,
    required this.onVerified,
    required this.onSkip,
  });

  final VoidCallback onBack;
  final VoidCallback onVerified;
  final VoidCallback onSkip;

  @override
  ConsumerState<_ApiKeyStep> createState() => _ApiKeyStepState();
}

class _ApiKeyStepState extends ConsumerState<_ApiKeyStep> {
  final _keyCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _verifyFailed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = ref.read(careSettingsProvider).value;
    _urlCtrl.text = current?.baseUrl ?? 'https://api.deepseek.com/v1';
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _keyCtrl.text = text;
      setState(() => _error = null);
    }
  }

  Future<void> _submit() async {
    final raw = _keyCtrl.text.trim();
    final hasSavedKey = ref.read(careSettingsProvider).value?.hasApiKey ?? false;
    if (raw.isEmpty && !hasSavedKey) {
      setState(() => _error = '请先粘贴你的 API Key。');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _verifyFailed = false;
    });

    final ctrl = ref.read(careSettingsProvider.notifier);
    try {
      final url = _urlCtrl.text.trim();
      final currentUrl = ref.read(careSettingsProvider).value?.baseUrl;
      if (url.isNotEmpty && url != currentUrl) await ctrl.setBaseUrl(url);
      if (raw.isNotEmpty) {
        await ctrl.saveApiKey(raw);
        _keyCtrl.clear();
      }
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = careFriendlyError(e.message);
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = careFriendlyError(e.toString());
      });
      return;
    }

    final ok = await ctrl.verifyDirectConnection();
    if (!mounted) return;
    if (ok) {
      widget.onVerified();
      return;
    }
    setState(() {
      _busy = false;
      _verifyFailed = true;
      _error = careFriendlyError(ref.read(careSettingsProvider).value?.lastError);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final masked = ref.watch(
      careSettingsProvider.select((s) => s.value?.maskedApiKey),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: _busy ? null : widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    '连接 DeepSeek',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '在 DeepSeek 开放平台（platform.deepseek.com）创建一个 API Key，'
                    '然后粘贴到下面。它会被加密保存在手机的安全区域里，不会上传到任何地方。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _keyCtrl,
                    enabled: !_busy,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: masked != null ? '已保存：$masked' : 'sk-…',
                      prefixIcon: const Icon(Icons.key_rounded),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: _obscure ? '显示' : '隐藏',
                            onPressed: () => setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                          IconButton(
                            tooltip: '粘贴',
                            onPressed: _busy ? null : _paste,
                            icon: const Icon(Icons.content_paste_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                      childrenPadding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
                      title: Text(
                        '使用其他兼容服务（可选）',
                        style: theme.textTheme.bodyMedium,
                      ),
                      children: [
                        TextField(
                          controller: _urlCtrl,
                          enabled: !_busy,
                          autocorrect: false,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: '服务地址',
                            helperText: '默认是 DeepSeek 官方地址，一般无需修改',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded,
                              color: scheme.onErrorContainer),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: scheme.onErrorContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('保存并测试连接'),
                  ),
                ),
                if (_verifyFailed && masked != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : widget.onSkip,
                    child: const Text('先跳过，直接开始'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadyStep extends StatelessWidget {
  const _ReadyStep({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_rounded,
                        size: 48, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    '一切就绪',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '连接成功，Care 随时为你服务。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onStart, child: const Text('开始聊天')),
          ),
        ],
      ),
    );
  }
}
