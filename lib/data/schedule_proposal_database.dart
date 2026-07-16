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

  Future<void> save(ScheduleRebalanceProposal proposal) async {
    await _ensureTable();
    await (await _db).insert('schedule_rebalance_proposals', {
      'id': proposal.id,
      'body_json': jsonEncode(proposal.toJson()),
      'fingerprint': proposal.fingerprint,
      'status': proposal.status.name,
      'created_at': proposal.createdAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateStatus(String id, ScheduleProposalStatus status) async {
    final proposal = await _byId(id);
    if (proposal == null) return;
    await save(proposal.copyWith(status: status));
  }

  Future<ScheduleRebalanceProposal?> markNotificationSent(String id) async {
    final proposal = await _byId(id);
    if (proposal == null || proposal.notificationSent) return proposal;
    final updated = proposal.copyWith(notificationSent: true);
    await save(updated);
    return updated;
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
