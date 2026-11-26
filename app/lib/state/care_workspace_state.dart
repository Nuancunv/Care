import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/care_workspace_bridge.dart';
import 'care_bots_state.dart';

final careWorkspacePlatformProvider = Provider<CareWorkspacePlatform>(
  (ref) => MethodChannelCareWorkspacePlatform(),
);

class CareWorkspaceState {
  const CareWorkspaceState({
    this.botId = kCareChiefBotId,
    this.isPrivate = false,
    this.files = const [],
  });

  final String botId;
  final bool isPrivate;
  final List<CareWorkspaceFile> files;

  /// Materials stored inside `<bot>/资料库/` for Notebook-style Q&A.
  List<CareWorkspaceFile> get libraryFiles =>
      files.where((f) => f.isInLibrary).toList();

  /// Generated code, HTML pages, and notes outside `资料库/`.
  List<CareWorkspaceFile> get outputFiles =>
      files.where((f) => !f.isInLibrary).toList();
}

/// Single owner of the active Bot's local Agent Workspace & Knowledge Library (`资料库/`).
final careWorkspaceProvider =
    AsyncNotifierProvider<CareWorkspaceController, CareWorkspaceState>(
  CareWorkspaceController.new,
);

class CareWorkspaceController extends AsyncNotifier<CareWorkspaceState> {
  @override
  Future<CareWorkspaceState> build() async {
    final bots = ref.watch(careBotsProvider).value;
    final active = bots?.activeBot ?? kChiefBotProfile;
    if (active.isPrivate && bots?.privacyUnlocked != true) {
      return CareWorkspaceState(botId: active.id, isPrivate: true);
    }
    try {
      final files = await ref.read(careWorkspacePlatformProvider).listFiles(
            botId: active.id,
            isPrivate: active.isPrivate,
          );
      return CareWorkspaceState(
        botId: active.id,
        isPrivate: active.isPrivate,
        files: files,
      );
    } catch (_) {
      return CareWorkspaceState(
        botId: active.id,
        isPrivate: active.isPrivate,
      );
    }
  }

  Future<void> refresh() async {
    final bots = ref.read(careBotsProvider).value;
    final active = bots?.activeBot ?? kChiefBotProfile;
    if (active.isPrivate && bots?.privacyUnlocked != true) {
      state = AsyncData(CareWorkspaceState(botId: active.id, isPrivate: true));
      return;
    }
    try {
      final files = await ref.read(careWorkspacePlatformProvider).listFiles(
            botId: active.id,
            isPrivate: active.isPrivate,
          );
      state = AsyncData(
        CareWorkspaceState(
          botId: active.id,
          isPrivate: active.isPrivate,
          files: files,
        ),
      );
    } catch (_) {}
  }

  Future<String?> readFile(String path) {
    final cur = state.value;
    final botId = cur?.botId ?? kCareChiefBotId;
    final isPrivate = cur?.isPrivate ?? false;
    return ref.read(careWorkspacePlatformProvider).readFile(
          botId: botId,
          isPrivate: isPrivate,
          path: path,
        );
  }

  Future<void> writeFile(String path, String content) async {
    final cur = state.value ?? await future;
    await ref.read(careWorkspacePlatformProvider).writeFile(
          botId: cur.botId,
          isPrivate: cur.isPrivate,
          path: path,
          content: content,
        );
    await refresh();
  }

  Future<void> addLibraryNote(String fileName, String content) async {
    final clean = fileName.trim();
    final path = clean.startsWith('$kCareLibraryFolder/')
        ? clean
        : '$kCareLibraryFolder/$clean';
    await writeFile(path, content);
  }

  Future<String?> importToLibrary() async {
    final cur = state.value ?? await future;
    final res = await ref.read(careWorkspacePlatformProvider).importToLibrary(
          botId: cur.botId,
          isPrivate: cur.isPrivate,
        );
    if (res == null || res['ok'] != true) return null;
    await refresh();
    return res['path']?.toString();
  }

  Future<String?> importStagedToBotLibrary({
    required String botId,
    required bool isPrivate,
    required String stagedPath,
    required String fileName,
  }) async {
    final res =
        await ref.read(careWorkspacePlatformProvider).importStagedToLibrary(
              botId: botId,
              isPrivate: isPrivate,
              stagedPath: stagedPath,
              fileName: fileName,
            );
    if (res == null || res['ok'] != true) return null;
    await refresh();
    return res['path']?.toString();
  }

  Future<List<CareLibrarySearchHit>> searchLibrary(String query) async {
    final cur = state.value ?? await future;
    return ref.read(careWorkspacePlatformProvider).searchLibrary(
          botId: cur.botId,
          isPrivate: cur.isPrivate,
          query: query,
        );
  }

  Future<void> deleteFile(String path) async {
    final cur = state.value ?? await future;
    await ref.read(careWorkspacePlatformProvider).deleteFile(
          botId: cur.botId,
          isPrivate: cur.isPrivate,
          path: path,
        );
    await refresh();
  }

  Future<bool> openHtmlPreview(String path) {
    final cur = state.value;
    return ref.read(careWorkspacePlatformProvider).openHtmlPreview(
          botId: cur?.botId ?? kCareChiefBotId,
          isPrivate: cur?.isPrivate ?? false,
          path: path,
        );
  }

  Future<bool> openWithExternalApp(String path) {
    final cur = state.value;
    return ref.read(careWorkspacePlatformProvider).openWithExternalApp(
          botId: cur?.botId ?? kCareChiefBotId,
          isPrivate: cur?.isPrivate ?? false,
          path: path,
        );
  }
}
