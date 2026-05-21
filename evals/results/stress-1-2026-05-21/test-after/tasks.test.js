const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { Readable, Writable } = require('node:stream');
const test = require('node:test');

const { createApp } = require('../src/app');
const { createDatabase, migrate } = require('../src/db');

class MockSocket extends Writable {
  constructor() {
    super();
    this.chunks = [];
    this.encrypted = false;
  }

  _write(chunk, encoding, callback) {
    this.chunks.push(Buffer.from(chunk));
    callback();
  }
}

class MockRequest extends Readable {
  constructor({ body, method, url }, socket) {
    const payload = body ? Buffer.from(JSON.stringify(body)) : Buffer.alloc(0);
    super();

    this._payload = payload;
    this._sent = false;
    this.headers = {
      host: 'localhost',
      ...(body
        ? {
            'content-length': String(payload.length),
            'content-type': 'application/json',
          }
        : {}),
    };
    this.method = method || 'GET';
    this.socket = socket;
    this.connection = socket;
    this.url = url;

    // Express 会替换请求对象的 prototype；把 _read 放在实例上避免丢失。
    this._read = () => {
      if (this._sent) {
        this.push(null);
        return;
      }

      this._sent = true;
      this.push(this._payload);
      this.push(null);
    };
  }
}

function parseRawResponse(rawResponse) {
  const headerEnd = rawResponse.indexOf('\r\n\r\n');
  const headers = rawResponse.slice(0, headerEnd);
  const bodyText = rawResponse.slice(headerEnd + 4);
  const status = Number(headers.match(/^HTTP\/1\.1 (\d+)/)[1]);

  return {
    body: bodyText ? JSON.parse(bodyText) : null,
    status,
  };
}

async function request(app, endpoint, options = {}) {
  return new Promise((resolve, reject) => {
    const socket = new MockSocket();
    const req = new MockRequest(
      { body: options.body, method: options.method || 'GET', url: endpoint },
      socket,
    );
    const res = new http.ServerResponse(req);

    req.res = res;
    res.req = req;
    res.assignSocket(socket);
    res.on('finish', () => {
      resolve(parseRawResponse(Buffer.concat(socket.chunks).toString('utf8')));
    });

    app.handle(req, res, reject);
  });
}

test('tasks API supports a full CRUD lifecycle', async (t) => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tasks-api-'));
  const db = createDatabase(path.join(tempDir, 'db.sqlite'));
  migrate(db);

  const app = createApp({ db });

  t.after(() => {
    db.close();
    fs.rmSync(tempDir, { force: true, recursive: true });
  });

  const created = await request(app, '/tasks', {
    method: 'POST',
    body: {
      subject: 'Write integration test',
      description: 'Cover the task CRUD lifecycle.',
      status: 'pending',
    },
  });

  assert.equal(created.status, 201);
  assert.equal(created.body.task.subject, 'Write integration test');
  assert.equal(created.body.task.description, 'Cover the task CRUD lifecycle.');
  assert.equal(created.body.task.status, 'pending');

  const id = created.body.task.id;

  const pendingTasks = await request(app, '/tasks?status=pending');
  assert.equal(pendingTasks.status, 200);
  assert.equal(pendingTasks.body.tasks.length, 1);
  assert.equal(pendingTasks.body.tasks[0].id, id);

  const updated = await request(app, `/tasks/${id}`, {
    method: 'PATCH',
    body: { status: 'completed' },
  });

  assert.equal(updated.status, 200);
  assert.equal(updated.body.task.id, id);
  assert.equal(updated.body.task.status, 'completed');

  const completedTasks = await request(app, '/tasks?status=completed');
  assert.equal(completedTasks.status, 200);
  assert.deepEqual(
    completedTasks.body.tasks.map((task) => task.id),
    [id],
  );

  const deleted = await request(app, `/tasks/${id}`, { method: 'DELETE' });
  assert.equal(deleted.status, 204);
  assert.equal(deleted.body, null);

  const allTasks = await request(app, '/tasks');
  assert.equal(allTasks.status, 200);
  assert.deepEqual(allTasks.body.tasks, []);
});
