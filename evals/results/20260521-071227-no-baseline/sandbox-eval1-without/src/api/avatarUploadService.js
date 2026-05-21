import { randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

export const MAX_AVATAR_BYTES = 5 * 1024 * 1024;

export const AVATAR_MIME_EXTENSIONS = Object.freeze({
  'image/gif': '.gif',
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp'
});

export class AvatarUploadError extends Error {
  constructor(message, statusCode = 400) {
    super(message);
    this.name = 'AvatarUploadError';
    this.statusCode = statusCode;
  }
}

export function validateAvatarFile(file) {
  if (!file) {
    throw new AvatarUploadError('avatar file is required');
  }

  if (!file.buffer || !Buffer.isBuffer(file.buffer)) {
    throw new AvatarUploadError('avatar must be uploaded as a buffered file');
  }

  if (!AVATAR_MIME_EXTENSIONS[file.mimetype]) {
    throw new AvatarUploadError('avatar must be a JPG, PNG, WebP, or GIF image');
  }

  if (file.size > MAX_AVATAR_BYTES) {
    throw new AvatarUploadError('avatar must be 5MB or smaller');
  }
}

function sanitizeUserId(userId) {
  const normalized = String(userId ?? '').trim();
  if (!normalized) {
    throw new AvatarUploadError('user id is required');
  }

  return normalized.replace(/[^a-zA-Z0-9_-]/g, '-');
}

function joinPublicUrl(publicBaseUrl, fileName) {
  return `${publicBaseUrl.replace(/\/+$/, '')}/${fileName}`;
}

export async function persistAvatarFile({
  file,
  publicBaseUrl = '/uploads/avatars',
  uploadDir,
  userId
}) {
  validateAvatarFile(file);

  if (!uploadDir) {
    throw new AvatarUploadError('avatar upload directory is required', 500);
  }

  const safeUserId = sanitizeUserId(userId);
  const extension = AVATAR_MIME_EXTENSIONS[file.mimetype];
  const fileName = `${safeUserId}-${randomUUID()}${extension}`;
  const storagePath = path.join(uploadDir, fileName);

  await mkdir(uploadDir, { recursive: true });
  await writeFile(storagePath, file.buffer);

  return {
    avatarMimeType: file.mimetype,
    avatarSizeBytes: file.size,
    avatarUpdatedAt: new Date(),
    avatarUrl: joinPublicUrl(publicBaseUrl, fileName),
    storagePath
  };
}

export async function updateUserAvatar({ avatar, db, userId }) {
  if (!db?.query) {
    return {
      id: userId,
      avatar_mime_type: avatar.avatarMimeType,
      avatar_size_bytes: avatar.avatarSizeBytes,
      avatar_updated_at: avatar.avatarUpdatedAt,
      avatar_url: avatar.avatarUrl
    };
  }

  const result = await db.query(
    `UPDATE users
       SET avatar_url = $1,
           avatar_mime_type = $2,
           avatar_size_bytes = $3,
           avatar_updated_at = $4
     WHERE id = $5
     RETURNING id, avatar_url, avatar_mime_type, avatar_size_bytes, avatar_updated_at`,
    [
      avatar.avatarUrl,
      avatar.avatarMimeType,
      avatar.avatarSizeBytes,
      avatar.avatarUpdatedAt,
      userId
    ]
  );

  if (!result.rows?.length) {
    throw new AvatarUploadError('user was not found', 404);
  }

  return result.rows[0];
}

export async function handleAvatarUpload({
  db,
  file,
  publicBaseUrl,
  uploadDir,
  userId
}) {
  const avatar = await persistAvatarFile({
    file,
    publicBaseUrl,
    uploadDir,
    userId
  });
  const user = await updateUserAvatar({ avatar, db, userId });

  return {
    avatarMimeType: user.avatar_mime_type,
    avatarSizeBytes: user.avatar_size_bytes,
    avatarUpdatedAt: user.avatar_updated_at,
    avatarUrl: user.avatar_url,
    userId: user.id
  };
}
