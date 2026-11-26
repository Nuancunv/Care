/// User-facing copy helpers.
///
/// Maps raw technical error strings and identifiers coming from the state layer
/// into friendly Chinese copy for everyday users (AGENTS.md §3.1). Raw details are
/// only ever shown on the「高级诊断」page.
library;

const kCareFlashModel = 'deepseek-flash';
const kCareV4ProModel = 'deepseek-v4-pro';

/// Turns a raw error string into a short, friendly sentence.
String careFriendlyError(String? raw) {
  const fallback = '出了点小问题，请稍后再试。';
  if (raw == null || raw.trim().isEmpty) return fallback;
  final s = raw.toLowerCase();

  if (s.contains('not configured') ||
      s.contains('configure your deepseek api key')) {
    return '还没有设置 API Key，请先在「设置」中填写。';
  }
  if (s.contains('without spaces') || s.contains('name=value')) {
    return 'API Key 格式不对：请只粘贴密钥本身，不要包含空格或「名称=」前缀。';
  }
  if (s.contains('http 401') ||
      s.contains('http 403') ||
      s.contains('rejected') ||
      s.contains('authentication')) {
    return 'API Key 无效或已失效，请检查后重新填写。';
  }
  if (s.contains('http 402') || s.contains('insufficient balance')) {
    return 'DeepSeek 账户余额不足，充值后即可继续使用。';
  }
  if (s.contains('http 429')) return '请求有点频繁，请稍等片刻再试。';
  if (s.contains('http 5')) return '模型服务暂时繁忙，请稍后再试。';
  if (s.contains('timeout') ||
      s.contains('socket') ||
      s.contains('host lookup') ||
      s.contains('connection') ||
      s.contains('network') ||
      s.contains('clientexception')) {
    return '网络连接不畅，请检查网络后重试。';
  }
  if (s.contains('must use https')) {
    return '自定义地址需要以 https:// 开头（本机地址除外）。';
  }
  if (s.contains('invalid api base url')) {
    return '服务地址格式不正确，请检查后重试。';
  }
  if (s.contains('session not ready')) return 'Care 还在准备中，请稍后再试。';
  return fallback;
}

/// Whether the error is something the user can fix in Settings.
bool careErrorNeedsSettings(String? raw) {
  if (raw == null) return false;
  final s = raw.toLowerCase();
  return s.contains('api key') ||
      s.contains('http 401') ||
      s.contains('http 403') ||
      s.contains('https') ||
      s.contains('base url');
}

String careModelLabel(String model) => switch (model) {
      kCareFlashModel => 'DeepSeek Flash',
      kCareV4ProModel => 'DeepSeek V4 Pro',
      _ => model,
    };

String careModelShortLabel(String model) => switch (model) {
      kCareFlashModel => 'Flash',
      kCareV4ProModel => 'V4 Pro',
      _ => model.length > 16 ? '${model.substring(0, 14)}…' : model,
    };

String careModelDescription(String model) => switch (model) {
      kCareFlashModel => '快速省钱、支持图文多模态，适合日常与轻量 Agent',
      kCareV4ProModel => '旗舰推理与编程主力，适合复杂规划与代码编写',
      _ => '已发现 / 自定义模型',
    };

String careEffortLabel(String effort) => switch (effort) {
      'none' => '关闭思考',
      'low' => '轻度思考',
      'high' => '深度思考',
      'max' => '极致思考',
      _ => '轻度思考',
    };

String careEffortShortLabel(String effort) => switch (effort) {
      'none' => '不思考',
      'low' => '低思考',
      'high' => '高思考',
      'max' => '极致',
      _ => '低思考',
    };

/// Friendly label for a native SafetyGate action identifier.
String careSafetyActionLabel(String action) => switch (action) {
      'accessibility_write' => '在其他应用中输入内容',
      'accessibility_click' => '在其他应用中点击操作',
      'send_external_message' => '替你发送消息',
      'send_email' => '替你发送邮件',
      'delete_file' => '删除文件',
      'payment_action' => '进行支付或下单',
      'system_settings_write' => '修改系统设置',
      'shell_high_risk' => '执行高风险系统操作',
      'privacy_cross_bot_export' => '把隐私空间的内容分享出去',
      'calendar_write' => '修改你的日历',
      'alarm_set' => '设置闹钟',
      'reminder_create' => '创建提醒',
      'memory_write' => '更新长期记忆',
      _ => '执行一项敏感操作',
    };

String careTwoDigits(int v) => v.toString().padLeft(2, '0');

String careClockTime(DateTime t) =>
    '${careTwoDigits(t.hour)}:${careTwoDigits(t.minute)}';

const _kWeekdays = ['一', '二', '三', '四', '五', '六', '日'];

String careDateLabel(DateTime t) =>
    '${t.month}月${t.day}日 星期${_kWeekdays[t.weekday - 1]}';

/// 今天 09:30 / 明天 09:30 / 11月28日 09:30
String careRelativeTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;
  final prefix = switch (diff) {
    0 => '今天',
    1 => '明天',
    -1 => '昨天',
    _ => '${t.month}月${t.day}日',
  };
  return '$prefix ${careClockTime(t)}';
}

String careRepeatLabel(int days) => switch (days) {
      <= 0 => '不重复',
      1 => '每天',
      7 => '每周',
      14 => '每两周',
      30 => '每月',
      _ => '每 $days 天',
    };

String careGreeting(DateTime t) => switch (t.hour) {
      < 5 => '夜深了',
      < 11 => '早上好',
      < 14 => '中午好',
      < 18 => '下午好',
      _ => '晚上好',
    };

/// Friendly copy for automation outcome / error strings from the state layer.
String? careFriendlyAutomation(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  const awaiting = 'Awaiting native SafetyGate approval: ';
  const completed = 'Completed: ';
  if (raw.startsWith(awaiting)) return '等待你确认：${raw.substring(awaiting.length)}';
  if (raw.startsWith(completed)) return '已完成：${raw.substring(completed.length)}';
  if (raw.contains('Emergency stop triggered')) return '已紧急停止，你已接管手机。';
  if (raw.contains('Emergency stop is active')) return '紧急停止中，恢复后才能继续自动操作。';
  if (raw.contains('Action refused')) return '这项操作被系统安全策略拒绝了。';
  if (RegExp(r'[\u4e00-\u9fff]').hasMatch(raw)) return raw;
  return '操作没有完成，请稍后再试。';
}

String careFormatCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 10000) return '${(n / 1000).toStringAsFixed(1)}K';
  return n.toString();
}
