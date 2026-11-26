import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Incremental tool-call delta streamed from an OpenAI-compatible `/chat/completions` SSE chunk.
class DirectToolCallDelta {
  const DirectToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsDelta = '',
  });

  final int index;
  final String? id;
  final String? name;
  final String argumentsDelta;
}

/// One incremental chunk emitted during direct OpenAI-compatible streaming.
class DirectStreamChunk {
  const DirectStreamChunk({
    this.contentDelta = '',
    this.reasoningDelta = '',
    this.toolCallDeltas = const [],
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
  });

  final String contentDelta;
  final String reasoningDelta;
  final List<DirectToolCallDelta> toolCallDeltas;
  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;
}

/// Supported thinking intensity levels for DeepSeek models (`deepseek-flash`, `deepseek-v4-pro`, etc.).
const kCareReasoningEfforts = <String>['none', 'low', 'high', 'max'];

/// Direct BYOK client talking straight to DeepSeek Official API (`https://api.deepseek.com/v1`)
/// or a user-configured OpenAI-compatible endpoint — ZERO third-party cloud relay (AGENTS.md §1.1).
class CareDeepSeekDirectClient {
  CareDeepSeekDirectClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  static const defaultBaseUrl = 'https://api.deepseek.com/v1';

  final http.Client _http;
  final bool _ownsClient;

  /// Validates endpoint URL: HTTPS required for remote hosts; HTTP allowed only for loopback.
  static Uri validateBaseUrl(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Invalid API base URL.');
    }
    final isLoopback = uri.host == '127.0.0.1' || uri.host == 'localhost';
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && isLoopback)) {
      throw const FormatException(
        'Remote API endpoints must use HTTPS (HTTP is only allowed for 127.0.0.1/localhost).',
      );
    }
    return uri;
  }

  /// Verifies the BYOK API key directly against `<baseUrl>/models` and returns all live model IDs
  /// (so future DeepSeek releases such as new V4/V5 models are automatically discovered).
  /// Never returns or logs the key value.
  Future<List<String>> verifyApiKey({
    required String apiKey,
    String baseUrl = defaultBaseUrl,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final base = validateBaseUrl(baseUrl);
    final url = Uri.parse('${base.toString()}/models');
    final resp = await _http.get(
      url,
      headers: {
        'Authorization': 'Bearer ${apiKey.trim()}',
        'Accept': 'application/json',
      },
    ).timeout(timeout);

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw Exception('API Key rejected by endpoint (HTTP ${resp.statusCode}).');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Endpoint check failed (HTTP ${resp.statusCode}).');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['data'] is List) {
      return (decoded['data'] as List)
          .whereType<Map>()
          .map((e) => e['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    }
    return const [
      'deepseek-flash',
      'deepseek-v4-pro',
    ];
  }

  /// Streams chat completions directly from `<baseUrl>/chat/completions` (SSE).
  /// Supports multimodal content arrays, `reasoning_effort` / `thinking`, and OpenAI `tools`.
  Stream<DirectStreamChunk> streamChat({
    required String apiKey,
    required String model,
    required List<Map<String, Object?>> messages,
    String baseUrl = defaultBaseUrl,
    String? reasoningEffort,
    List<Map<String, Object?>>? tools,
  }) async* {
    final base = validateBaseUrl(baseUrl);
    final uri = Uri.parse('${base.toString()}/chat/completions');

    Map<String, Object?> buildPayload({required bool includeThinkingFields}) {
      final body = <String, Object?>{
        'model': model,
        'messages': messages,
        'stream': true,
        'stream_options': {'include_usage': true},
      };
      if (includeThinkingFields &&
          reasoningEffort != null &&
          reasoningEffort.isNotEmpty) {
        if (reasoningEffort == 'none') {
          if (model != 'deepseek-reasoner') {
            body['thinking'] = {'type': 'disabled'};
          }
        } else if (kCareReasoningEfforts.contains(reasoningEffort)) {
          body['reasoning_effort'] = reasoningEffort;
          body['thinking'] = {'type': 'enabled'};
        }
      }
      if (tools != null && tools.isNotEmpty) {
        body['tools'] = tools;
        body['tool_choice'] = 'auto';
      }
      return body;
    }

    Future<http.StreamedResponse> sendOnce(Map<String, Object?> payload) {
      final req = http.Request('POST', uri)
        ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode(payload);
      return _http.send(req).timeout(const Duration(seconds: 45));
    }

    var streamed = await sendOnce(buildPayload(includeThinkingFields: true));
    // Graceful compatibility fallback for third-party gateways that reject `thinking`/`reasoning_effort`.
    if (streamed.statusCode == 400 &&
        reasoningEffort != null &&
        reasoningEffort.isNotEmpty) {
      final firstErr = await streamed.stream.bytesToString();
      final lower = firstErr.toLowerCase();
      if (lower.contains('thinking') ||
          lower.contains('reasoning_effort') ||
          lower.contains('unknown') ||
          lower.contains('unrecognized')) {
        streamed = await sendOnce(buildPayload(includeThinkingFields: false));
      } else {
        throw Exception(
          'Direct API request failed (HTTP 400): ${firstErr.length > 200 ? firstErr.substring(0, 200) : firstErr}',
        );
      }
    }

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final errBody = await streamed.stream.bytesToString();
      throw Exception(
        'Direct API request failed (HTTP ${streamed.statusCode}): ${errBody.length > 200 ? errBody.substring(0, 200) : errBody}',
      );
    }

    final lines = streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') break;
      final Object? parsed;
      try {
        parsed = jsonDecode(payload);
      } catch (_) {
        continue;
      }
      if (parsed is! Map) continue;

      String content = '';
      String reasoning = '';
      String? finishReason;
      final toolDeltas = <DirectToolCallDelta>[];

      final choices = parsed['choices'];
      if (choices is List && choices.isNotEmpty && choices.first is Map) {
        final choice = choices.first as Map;
        if (choice['finish_reason'] is String) {
          finishReason = choice['finish_reason'] as String;
        }
        final delta = choice['delta'];
        if (delta is Map) {
          if (delta['content'] is String) content = delta['content'] as String;
          if (delta['reasoning_content'] is String) {
            reasoning = delta['reasoning_content'] as String;
          }
          final rawTools = delta['tool_calls'];
          if (rawTools is List) {
            for (final item in rawTools.whereType<Map>()) {
              final idx = (item['index'] as num?)?.toInt() ?? 0;
              final fn = item['function'];
              toolDeltas.add(
                DirectToolCallDelta(
                  index: idx,
                  id: item['id']?.toString(),
                  name: fn is Map ? fn['name']?.toString() : null,
                  argumentsDelta:
                      fn is Map ? (fn['arguments']?.toString() ?? '') : '',
                ),
              );
            }
          }
        }
      }

      int? promptTokens;
      int? completionTokens;
      final usage = parsed['usage'];
      if (usage is Map) {
        if (usage['prompt_tokens'] is int) {
          promptTokens = usage['prompt_tokens'] as int;
        }
        if (usage['completion_tokens'] is int) {
          completionTokens = usage['completion_tokens'] as int;
        }
      }

      if (content.isNotEmpty ||
          reasoning.isNotEmpty ||
          toolDeltas.isNotEmpty ||
          finishReason != null ||
          promptTokens != null ||
          completionTokens != null) {
        yield DirectStreamChunk(
          contentDelta: content,
          reasoningDelta: reasoning,
          toolCallDeltas: toolDeltas,
          finishReason: finishReason,
          promptTokens: promptTokens,
          completionTokens: completionTokens,
        );
      }
    }
  }

  /// Direct local HTTPS webpage fetch helper for Care's `web_fetch` agent tool (zero cloud relay).
  Future<String> fetchWebText(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('URL must start with https:// or http://');
    }
    final resp = await _http.get(
      uri,
      headers: {'User-Agent': 'Care-Personal-Agent/0.1'},
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final raw = utf8.decode(resp.bodyBytes, allowMalformed: true);
    // Strip script/style blocks and HTML tags into readable plain text.
    var cleaned = raw
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.length > 6000) {
      cleaned = '${cleaned.substring(0, 6000)}… [truncated]';
    }
    return cleaned;
  }

  void close() {
    if (_ownsClient) _http.close();
  }
}
