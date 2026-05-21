const path = require('node:path');
const Database = require('better-sqlite3');

const TASK_STATUSES = ['pending', 'in_progress', 'completed'];
const TASK_STATUS_SET = new Set(TASK_STATUSES);

function defaultDbPath() {
  return process.env.DB_PATH || path.join(__dirname, '..', 'db.sqlite');
}

function createDatabase(dbPath = defaultDbPath()) {
  const db = new Database(dbPath);
  db.pragma('foreign_keys = ON');
  return db;
}

function migrate(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS tasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subject TEXT NOT NULL CHECK (length(trim(subject)) > 0),
      description TEXT NOT NULL,
      status TEXT NOT NULL CHECK (status IN ('pending', 'in_progress', 'completed')),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
  `);
}

module.exports = {
  TASK_STATUSES,
  TASK_STATUS_SET,
  createDatabase,
  defaultDbPath,
  migrate,
};
