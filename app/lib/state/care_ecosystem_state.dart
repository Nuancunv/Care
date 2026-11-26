import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/care_m2_bridge.dart';

class CareCalendarEvent {
  const CareCalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.location = '',
    this.allDay = false,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String location;
  final bool allDay;

  factory CareCalendarEvent.fromMap(Map<String, Object?> map) =>
      CareCalendarEvent(
        id: map['id']?.toString() ?? '',
        title: map['title']?.toString() ?? '(无标题)',
        start: DateTime.fromMillisecondsSinceEpoch(
          (map['startMs'] as num?)?.toInt() ?? 0,
        ),
        end: DateTime.fromMillisecondsSinceEpoch(
          (map['endMs'] as num?)?.toInt() ?? 0,
        ),
        location: map['location']?.toString() ?? '',
        allDay: map['allDay'] == true,
      );
}

class CareNoticeItem {
  const CareNoticeItem({
    required this.packageName,
    required this.title,
    required this.text,
    required this.postedAt,
  });

  final String packageName;
  final String title;
  final String text;
  final DateTime postedAt;

  factory CareNoticeItem.fromMap(Map<String, Object?> map) => CareNoticeItem(
        packageName: map['packageName']?.toString() ?? '',
        title: map['title']?.toString() ?? '',
        text: map['text']?.toString() ?? '',
        postedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['postedAtMs'] as num?)?.toInt() ?? 0,
        ),
      );
}

class CareEcosystemState {
  const CareEcosystemState({
    this.calendarReadGranted = false,
    this.calendarWriteGranted = false,
    this.upcomingEvents = const [],
    this.noticeAccessEnabled = false,
    this.noticeAllowList = const [],
    this.recentNotices = const [],
  });

  final bool calendarReadGranted;
  final bool calendarWriteGranted;
  final List<CareCalendarEvent> upcomingEvents;
  final bool noticeAccessEnabled;
  final List<String> noticeAllowList;
  final List<CareNoticeItem> recentNotices;

  CareEcosystemState copyWith({
    bool? calendarReadGranted,
    bool? calendarWriteGranted,
    List<CareCalendarEvent>? upcomingEvents,
    bool? noticeAccessEnabled,
    List<String>? noticeAllowList,
    List<CareNoticeItem>? recentNotices,
  }) =>
      CareEcosystemState(
        calendarReadGranted: calendarReadGranted ?? this.calendarReadGranted,
        calendarWriteGranted: calendarWriteGranted ?? this.calendarWriteGranted,
        upcomingEvents: upcomingEvents ?? this.upcomingEvents,
        noticeAccessEnabled: noticeAccessEnabled ?? this.noticeAccessEnabled,
        noticeAllowList: noticeAllowList ?? this.noticeAllowList,
        recentNotices: recentNotices ?? this.recentNotices,
      );
}

final careEcosystemPlatformProvider = Provider<CareEcosystemPlatform>(
  (ref) => MethodChannelCareEcosystemPlatform(),
);

/// Single owner of on-demand Android system calendar & notification inbox state (M2).
final careEcosystemProvider =
    AsyncNotifierProvider<CareEcosystemController, CareEcosystemState>(
  CareEcosystemController.new,
);

class CareEcosystemController extends AsyncNotifier<CareEcosystemState> {
  @override
  Future<CareEcosystemState> build() async {
    return _loadAll();
  }

  Future<CareEcosystemState> _loadAll({int daysAhead = 7}) async {
    final platform = ref.read(careEcosystemPlatformProvider);
    bool readGranted = false;
    bool writeGranted = false;
    List<CareCalendarEvent> events = const [];
    bool noticeEnabled = false;
    List<String> allowList = const [];
    List<CareNoticeItem> notices = const [];

    try {
      final perm = await platform.calendarPermissionStatus();
      readGranted = perm['read'] == true;
      writeGranted = perm['write'] == true;
      if (readGranted) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final res = await platform.readCalendarEvents(
          startMs: now,
          endMs: now + daysAhead * 86400000,
        );
        final rawEvents = res['events'];
        if (rawEvents is List) {
          events = rawEvents
              .whereType<Map>()
              .map(
                (m) => CareCalendarEvent.fromMap(
                  m.map((k, v) => MapEntry(k.toString(), v)),
                ),
              )
              .toList();
        }
      }
    } catch (_) {}

    try {
      final noticeStatus = await platform.noticeAccessStatus();
      noticeEnabled = noticeStatus['enabled'] == true;
      final rawAllow = noticeStatus['allowList'];
      if (rawAllow is List) {
        allowList = rawAllow.map((e) => e.toString()).toList();
      }
      final rawNotices = await platform.getRecentNotices();
      notices = rawNotices.map(CareNoticeItem.fromMap).toList();
    } catch (_) {}

    return CareEcosystemState(
      calendarReadGranted: readGranted,
      calendarWriteGranted: writeGranted,
      upcomingEvents: events,
      noticeAccessEnabled: noticeEnabled,
      noticeAllowList: allowList,
      recentNotices: notices,
    );
  }

  Future<bool> requestCalendarPermission() async {
    final granted =
        await ref.read(careEcosystemPlatformProvider).requestCalendarPermission();
    state = AsyncData(await _loadAll());
    return granted;
  }

  Future<void> refresh({int daysAhead = 7}) async {
    state = AsyncData(await _loadAll(daysAhead: daysAhead));
  }

  Future<bool> createCalendarEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String? location,
    String? notes,
  }) async {
    final res = await ref.read(careEcosystemPlatformProvider).createCalendarEvent(
          title: title.trim(),
          startMs: start.millisecondsSinceEpoch,
          endMs: end.millisecondsSinceEpoch,
          location: location,
          notes: notes,
        );
    final created = res['created'] == true;
    if (created) await refresh();
    return created;
  }

  Future<bool> openNoticeAccessSettings() =>
      ref.read(careEcosystemPlatformProvider).openNoticeAccessSettings();

  Future<void> setNoticeAllowList(List<String> packages) async {
    await ref.read(careEcosystemPlatformProvider).setNoticeAllowList(packages);
    await refresh();
  }

  Future<void> clearNotices() async {
    await ref.read(careEcosystemPlatformProvider).clearNotices();
    final current = state.value ?? await future;
    state = AsyncData(current.copyWith(recentNotices: const []));
  }
}
