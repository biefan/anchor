const express = require('express');
const { TASK_STATUS_SET } = require('./db');

function parseTaskId(rawId) {
  const id = Number(rawId);
  return Number.isInteger(id) && id > 0 ? id : null;
}

function isValidStatus(status) {
  return typeof status === 'string' && TASK_STATUS_SET.has(status);
}

function getTaskById(db, id) {
  return db
    .prepare(
      `SELECT
        id,
        subject,
        description,
        status,
        created_at AS createdAt,
        updated_at AS updatedAt
      FROM tasks
      WHERE id = ?`,
    )
    .get(id);
}

function validateCreatePayload(body) {
  if (!body || typeof body !== 'object') {
    return 'Request body must be a JSON object.';
  }

  if (typeof body.subject !== 'string' || body.subject.trim().length === 0) {
    return 'subject must be a non-empty string.';
  }

  if (typeof body.description !== 'string') {
    return 'description must be a string.';
  }

  if (!isValidStatus(body.status)) {
    return 'status must be one of: pending, in_progress, completed.';
  }

  return null;
}

function createApp({ db }) {
  if (!db) {
    throw new Error('createApp requires a database instance.');
  }

  const app = express();
  app.use(express.json());

  app.post('/tasks', (req, res) => {
    const error = validateCreatePayload(req.body);
    if (error) {
      return res.status(400).json({ error });
    }

    const result = db
      .prepare(
        `INSERT INTO tasks (subject, description, status)
         VALUES (?, ?, ?)`,
      )
      .run(req.body.subject.trim(), req.body.description, req.body.status);

    return res.status(201).json({ task: getTaskById(db, result.lastInsertRowid) });
  });

  app.get('/tasks', (req, res) => {
    const { status } = req.query;
    if (Array.isArray(status) || (status !== undefined && !isValidStatus(status))) {
      return res.status(400).json({
        error: 'status must be one of: pending, in_progress, completed.',
      });
    }

    const query = `
      SELECT
        id,
        subject,
        description,
        status,
        created_at AS createdAt,
        updated_at AS updatedAt
      FROM tasks
      ${status ? 'WHERE status = ?' : ''}
      ORDER BY id ASC
    `;
    const tasks = status ? db.prepare(query).all(status) : db.prepare(query).all();

    return res.json({ tasks });
  });

  app.patch('/tasks/:id', (req, res) => {
    const id = parseTaskId(req.params.id);
    if (!id) {
      return res.status(400).json({ error: 'id must be a positive integer.' });
    }

    if (!req.body || !isValidStatus(req.body.status)) {
      return res.status(400).json({
        error: 'status must be one of: pending, in_progress, completed.',
      });
    }

    const result = db
      .prepare(
        `UPDATE tasks
         SET status = ?, updated_at = datetime('now')
         WHERE id = ?`,
      )
      .run(req.body.status, id);

    if (result.changes === 0) {
      return res.status(404).json({ error: 'Task not found.' });
    }

    return res.json({ task: getTaskById(db, id) });
  });

  app.delete('/tasks/:id', (req, res) => {
    const id = parseTaskId(req.params.id);
    if (!id) {
      return res.status(400).json({ error: 'id must be a positive integer.' });
    }

    const result = db.prepare('DELETE FROM tasks WHERE id = ?').run(id);
    if (result.changes === 0) {
      return res.status(404).json({ error: 'Task not found.' });
    }

    return res.status(204).send();
  });

  app.use((err, req, res, next) => {
    if (err instanceof SyntaxError && 'body' in err) {
      return res.status(400).json({ error: 'Request body must be valid JSON.' });
    }

    return next(err);
  });

  return app;
}

module.exports = {
  createApp,
};
