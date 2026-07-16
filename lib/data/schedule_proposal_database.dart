import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../services/schedule_load_service.dart';
import 'local_database.dart';

class ScheduleProposalDatabase {
  final SumiLocalDatabase _store;
  ScheduleProposalDatabase(this._store);

  Future<Database> get _db => _store.database;

  Future<void> _ensureTable() async {
    final db = await _db;
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS schedule_rebalance_proposals (
      id TEXT PRIMARY KEY, body_json TEXT NOT NULL, fingerprint TEXT NOT NULL,
      status TEXT NOT NULL, created_at TEXT NOT NULL
    )''',
    );
  }

  Future<ScheduleRebalanceProposal?> latestPending() async {
    await _ensureTable();
    final rows = await (await _db).query(
      'schedule_rebalance_proposals',
      where: 'status = ?',
      whereArgs: [ScheduleProposalStatus.pending.name],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<ScheduleRebalanceProposal?> latest() async {
    await _ensureTable();
    final rows = await (await _db).query(
      'schedule_rebalance_proposals',
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<bool> hasFingerprint(String fingerprint) async {
    await _ensureTable();
    final rows = await (await _db).query(
      'schedule_rebalance_proposals',
      columns: ['id'],
      where: 'fingerprint = ?',
      whereArgs: [fingerprint],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Every persisted write receives a fresh presentation timestamp. The JSON
  /// payload is intentionally the source of truth so this remains compatible
  /// with the existing table on installed devices.
  Future<ScheduleRebalanceProposal> save(
    ScheduleRebalanceProposal proposal,
  ) async {
    await _ensureTable();
    final persisted = proposal.copyWith(updatedAt: DateTime.now());
    await (await _db).insert('schedule_rebalance_proposals', {
      'id': persisted.id,
      'body_json': jsonEncode(persisted.toJson()),
      'fingerprint': persisted.fingerprint,
      'status': persisted.status.name,
      'created_at': persisted.createdAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return persisted;
  }

  Future<ScheduleRebalanceProposal?> updateStatus(
    String id,
    ScheduleProposalStatus status,
  ) async {
    final proposal = await _byId(id);
    if (proposal == null) return null;
    final updated = status == ScheduleProposalStatus.accepted
        ? proposal.complete(movedCount: proposal.moves.length)
        : proposal.copyWith(status: status);
    return save(updated);
  }

  /// Updates only the stage used to place the system card in the chat stream.
  /// [clearDisplayAnchor] allows a delayed card to become immediately visible.
  Future<ScheduleRebalanceProposal?> updatePresentation(
    String id, {
    ScheduleProposalStage? stage,
    String? displayAnchorMessageId,
    bool clearDisplayAnchor = false,
  }) async {
    final proposal = await _byId(id);
    if (proposal == null) return null;
    var updated = proposal.copyWith(stage: stage);
    if (clearDisplayAnchor || displayAnchorMessageId != null) {
      updated = updated.copyWith(
        displayAnchorMessageId: clearDisplayAnchor
            ? null
            : displayAnchorMessageId,
      );
    }
    return save(updated);
  }

  /// A card created while a reply is streaming is hidden until that reply
  /// settles. Once it settles, remove the transient anchor so the card is
  /// rendered at the end of that conversation even if the reply failed.
  Future<bool> releaseDisplayAnchor({
    required String conversationId,
    required String assistantMessageId,
  }) async {
    await _ensureTable();
    final rows = await (await _db).query(
      'schedule_rebalance_proposals',
      columns: ['body_json'],
    );
    final matches = rows
        .map(_fromRow)
        .where(
          (proposal) =>
              proposal.conversationId == conversationId &&
              proposal.displayAnchorMessageId == assistantMessageId &&
              proposal.status != ScheduleProposalStatus.dismissed,
        )
        .toList(growable: false);
    for (final proposal in matches) {
      await updatePresentation(proposal.id, clearDisplayAnchor: true);
    }
    return matches.isNotEmpty;
  }

  /// Persists the actual number of moved items instead of assuming every
  /// preview item stayed eligible until the user confirmed it.
  Future<ScheduleRebalanceProposal?> complete(
    String id, {
    required int movedCount,
    String? displayAnchorMessageId,
  }) async {
    final proposal = await _byId(id);
    if (proposal == null) return null;
    var updated = proposal.complete(movedCount: movedCount);
    if (displayAnchorMessageId != null) {
      updated = updated.copyWith(
        displayAnchorMessageId: displayAnchorMessageId,
      );
    }
    return save(updated);
  }

  /// Completed cards are history, pending cards are actionable, and dismissed
  /// cards deliberately disappear from their date conversation.
  Future<List<ScheduleRebalanceProposal>> visibleForConversation(
    String conversationId,
  ) async {
    await _ensureTable();
    final rows = await (await _db).query(
      'schedule_rebalance_proposals',
      columns: ['body_json'],
      orderBy: 'created_at ASC',
    );
    return rows
        .map(_fromRow)
        .where(
          (proposal) =>
              proposal.conversationId == conversationId &&
              proposal.status != ScheduleProposalStatus.dismissed,
        )
        .toList(growable: false);
  }

  Future<ScheduleRebalanceProposal?> markNotificationSent(
    String id, {
    required String date,
    required double risk,
  }) async {
    final proposal = await _byId(id);
    if (proposal == null) return null;
    final sameDay = proposal.lastNotificationDate == date;
    final updated = proposal.copyWith(
      notificationSent: true,
      lastNotificationDate: date,
      lastNotificationRisk: risk,
      notificationsOnLastDate: sameDay
          ? proposal.notificationsOnLastDate + 1
          : 1,
    );
    await save(updated);
    return updated;
  }

  /// At most one daily notification, with one extra allowance for a material
  /// risk increase. This scans durable proposals so replacing a card cannot
  /// bypass the limit.
  Future<bool> canNotify({required String date, required double risk}) async {
    await _ensureTable();
    final rows = await (await _db).query(
      'schedule_rebalance_proposals',
      columns: ['body_json'],
    );
    final notified = rows
        .map(_fromRow)
        .where((proposal) => proposal.lastNotificationDate == date)
        .toList(growable: false);
    if (notified.isEmpty) return true;
    final count = notified.fold<int>(
      0,
      (sum, proposal) => sum + proposal.notificationsOnLastDate,
    );
    final highestRisk = notified.fold<double>(
      0,
      (max, proposal) =>
          proposal.lastNotificationRisk != null &&
              proposal.lastNotificationRisk! > max
          ? proposal.lastNotificationRisk!
          : max,
    );
    return count < 2 && risk >= highestRisk + .15;
  }

  Future<ScheduleRebalanceProposal?> _byId(String id) async {
    await _ensureTable();
    final rows = await (await _db).query(
      'schedule_rebalance_proposals',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<void> clearAll() async {
    await _ensureTable();
    await (await _db).delete('schedule_rebalance_proposals');
  }

  ScheduleRebalanceProposal _fromRow(Map<String, Object?> row) {
    final raw = row['body_json'] as String? ?? '{}';
    final parsed = _parse(raw);
    return ScheduleRebalanceProposal.fromJson(parsed);
  }

  Map<String, Object?> _parse(String raw) {
    try {
      final value = raw.startsWith('{') ? raw : '{}';
      return (jsonDecode(value) as Map).cast<String, Object?>();
    } catch (_) {
      return {};
    }
  }
}
