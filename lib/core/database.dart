import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Explicit SQL keeps migrations reviewable without generated schema files.
class WorkspaceDatabase extends GeneratedDatabase {
  WorkspaceDatabase(File file) : super(NativeDatabase.createInBackground(file));
  WorkspaceDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement('''CREATE TABLE objects (
        id TEXT PRIMARY KEY, kind TEXT NOT NULL, payload TEXT NOT NULL,
        revision INTEGER NOT NULL, device TEXT NOT NULL,
        updated TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
      )''');
      await customStatement(
        'CREATE INDEX objects_kind ON objects(kind, deleted, updated)',
      );
      await customStatement('''CREATE TABLE outbox (
        id TEXT PRIMARY KEY, revision INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt TEXT, error TEXT
      )''');
      await customStatement(
        'CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await customStatement('''CREATE VIRTUAL TABLE search_index USING fts5(
        id UNINDEXED, title, body, tokenize='unicode61'
      )''');
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys=ON');
      await customStatement('PRAGMA journal_mode=WAL');
      await customStatement('PRAGMA busy_timeout=5000');
    },
  );
}
