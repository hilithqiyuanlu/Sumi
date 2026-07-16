import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';

enum ReminderScheduleQuality { exact, inexact, unavailable }

/// 系统级提醒的最小接口，方便计时逻辑独立测试。
abstract interface class ReminderScheduler {
  Future<ReminderScheduleQuality> schedule(StudyTimer timer);
  Future<void> showNow(StudyTimer timer);
  Future<void> cancel(String timerId);
  Future<void> cancelAll();
}

/// 使用系统通知提供后台、锁屏和 App 关闭后的声音与震动提醒。
class SystemReminderService implements ReminderScheduler {
  static const _channelId = 'sumi_learning_reminders';
  static const _channelName = '学习提醒';
  static const _channelDescription = '学习计时和闹钟到点提醒';

  final FlutterLocalNotificationsPlugin _notifications;
  bool _initialized = false;

  SystemReminderService({FlutterLocalNotificationsPlugin? notifications})
    : _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  Future<void> _initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } catch (_) {
      // 时区读取失败时保留 timezone 的默认 UTC，仍可安全调度通知。
    }

    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          defaultPresentAlert: true,
          defaultPresentBanner: true,
          defaultPresentList: true,
          defaultPresentSound: true,
        ),
      ),
    );
    _initialized = true;
  }

  @override
  Future<ReminderScheduleQuality> schedule(StudyTimer timer) async {
    final triggerAt = timer.triggerAt;
    if (triggerAt == null || !triggerAt.isAfter(DateTime.now())) {
      return ReminderScheduleQuality.unavailable;
    }
    try {
      await _initialize();
      final quality = await _requestPermissions();
      if (quality == ReminderScheduleQuality.unavailable) return quality;
      await _notifications.zonedSchedule(
        id: _notificationId(timer.id),
        title: _title(timer),
        body: _body(timer),
        scheduledDate: tz.TZDateTime.from(triggerAt, tz.local),
        notificationDetails: _details,
        payload: timer.id,
        androidScheduleMode: quality == ReminderScheduleQuality.exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return quality;
    } catch (_) {
      return ReminderScheduleQuality.unavailable;
    }
  }

  @override
  Future<void> showNow(StudyTimer timer) async {
    try {
      await _initialize();
      final quality = await _requestPermissions();
      if (quality == ReminderScheduleQuality.unavailable) return;
      await _notifications.show(
        id: _notificationId(timer.id),
        title: _title(timer),
        body: _body(timer),
        notificationDetails: _details,
        payload: timer.id,
      );
    } catch (_) {
      // 前台触发时，触觉反馈仍会作为最后的兜底。
    }
  }

  /// 普通的负荷提醒，不申请精确闹钟权限，也不承诺后台持续检测。
  Future<void> showScheduleRebalanceAlert({required int moveCount}) async {
    try {
      await _initialize();
      if (!await _requestNotificationPermission()) return;
      await _notifications.show(
        id: 713021,
        title: '本周安排较满',
        body: moveCount > 0
            ? 'Sumi 已准备 $moveCount 项可调整的排期方案。'
            : 'Sumi 发现本周任务较集中，打开 App 查看建议。',
        notificationDetails: _details,
        payload: 'schedule_rebalance',
      );
    } catch (_) {
      // 通知不可用时，前台卡片仍然保留。
    }
  }

  @override
  Future<void> cancel(String timerId) async {
    try {
      await _initialize();
      await _notifications.cancel(id: _notificationId(timerId));
    } catch (_) {
      // 取消失败不能阻断计时器本身的状态更新。
    }
  }

  @override
  Future<void> cancelAll() async {
    try {
      await _initialize();
      await _notifications.cancelAll();
    } catch (_) {
      // 清空本地数据仍需继续。
    }
  }

  Future<ReminderScheduleQuality> _requestPermissions() async {
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      var notificationsEnabled =
          await android.areNotificationsEnabled() ?? true;
      if (!notificationsEnabled) {
        notificationsEnabled =
            await android.requestNotificationsPermission() ?? false;
      }
      if (!notificationsEnabled) return ReminderScheduleQuality.unavailable;

      var exact = await android.canScheduleExactNotifications() ?? false;
      if (!exact) {
        await android.requestExactAlarmsPermission();
        exact = await android.canScheduleExactNotifications() ?? false;
      }
      return exact
          ? ReminderScheduleQuality.exact
          : ReminderScheduleQuality.inexact;
    }

    final ios = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final granted =
          await ios.requestPermissions(
            alert: true,
            badge: false,
            sound: true,
          ) ??
          false;
      return granted
          ? ReminderScheduleQuality.exact
          : ReminderScheduleQuality.unavailable;
    }
    return ReminderScheduleQuality.unavailable;
  }

  Future<bool> _requestNotificationPermission() async {
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final enabled = await android.areNotificationsEnabled() ?? false;
      return enabled ||
          (await android.requestNotificationsPermission() ?? false);
    }
    final ios = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return ios == null ||
        await ios.requestPermissions(alert: true, badge: false, sound: true) ==
            true;
  }

  NotificationDetails get _details => NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 700, 250, 900, 250, 900]),
      category: AndroidNotificationCategory.alarm,
    ),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    ),
  );

  String _title(StudyTimer timer) =>
      timer.kind == StudyTimerKind.alarm ? 'Sumi 闹钟' : '学习时间到';

  String _body(StudyTimer timer) => timer.kind == StudyTimerKind.alarm
      ? '${timer.title}，现在开始吧。'
      : '${timer.title} 已完成，休息一下再继续。';

  int _notificationId(String timerId) => timerId.hashCode & 0x7fffffff;
}
