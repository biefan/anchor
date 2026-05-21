import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import {
  AvatarUploadError,
  handleAvatarUpload
} from '../../src/api/avatarUploadService.js';

function pngFixture() {
  return Buffer.from([
    0x89, 0x50, 0x4e, 0x47,
    0x0d, 0x0a, 0x1a, 0x0a
  ]);
}

describe('avatar upload integration', () => {
  it('persists the image and updates the user avatar columns', async () => {
    const uploadDir = await mkdtemp(path.join(tmpdir(), 'avatar-upload-'));
    const queries = [];
    const db = {
      async query(sql, params) {
        queries.push({ params, sql });

        return {
          rows: [{
            id: params[4],
            avatar_mime_type: params[1],
            avatar_size_bytes: params[2],
            avatar_updated_at: params[3],
            avatar_url: params[0]
          }]
        };
      }
    };
    const buffer = pngFixture();

    const result = await handleAvatarUpload({
      db,
      file: {
        buffer,
        mimetype: 'image/png',
        originalname: 'face.png',
        size: buffer.length
      },
      publicBaseUrl: '/uploads/avatars',
      uploadDir,
      userId: 'user-123'
    });

    assert.equal(result.userId, 'user-123');
    assert.equal(result.avatarMimeType, 'image/png');
    assert.equal(result.avatarSizeBytes, buffer.length);
    assert.match(result.avatarUrl, /^\/uploads\/avatars\/user-123-[a-f0-9-]+\.png$/);
    assert.equal(queries.length, 1);
    assert.match(queries[0].sql, /UPDATE users/);
    assert.deepEqual(queries[0].params.slice(0, 3), [
      result.avatarUrl,
      'image/png',
      buffer.length
    ]);

    const storedFileName = result.avatarUrl.split('/').at(-1);
    const storedPath = path.join(uploadDir, storedFileName);

    assert.equal((await stat(storedPath)).size, buffer.length);
    assert.deepEqual(await readFile(storedPath), buffer);
  });

  it('rejects non-image avatar uploads before writing to storage', async () => {
    const uploadDir = await mkdtemp(path.join(tmpdir(), 'avatar-upload-'));

    await assert.rejects(
      () => handleAvatarUpload({
        file: {
          buffer: Buffer.from('not an image'),
          mimetype: 'text/plain',
          originalname: 'notes.txt',
          size: 12
        },
        uploadDir,
        userId: 'user-123'
      }),
      (error) => error instanceof AvatarUploadError
        && error.message === 'avatar must be a JPG, PNG, WebP, or GIF image'
    );
  });

  it('ships a migration for the persisted avatar metadata', async () => {
    const migration = await readFile(
      path.resolve('migrations/202605210001_add_user_avatar_fields.sql'),
      'utf8'
    );

    assert.match(migration, /ADD COLUMN IF NOT EXISTS avatar_url TEXT/i);
    assert.match(migration, /ADD COLUMN IF NOT EXISTS avatar_mime_type VARCHAR\(64\)/i);
    assert.match(migration, /ADD COLUMN IF NOT EXISTS avatar_size_bytes INTEGER/i);
    assert.match(migration, /ADD COLUMN IF NOT EXISTS avatar_updated_at TIMESTAMPTZ/i);
    assert.match(migration, /avatar_size_bytes <= 5242880/i);
  });
});
