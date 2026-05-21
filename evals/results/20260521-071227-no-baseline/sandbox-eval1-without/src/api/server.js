import express from 'express';
import path from 'node:path';
import { avatarUploadErrorHandler, createAvatarRouter } from './avatarRoutes.js';

export function createApiApp({
  db,
  publicBaseUrl = '/uploads/avatars',
  uploadDir = process.env.AVATAR_UPLOAD_DIR || path.join(process.cwd(), 'uploads', 'avatars')
} = {}) {
  const app = express();

  app.use(publicBaseUrl, express.static(uploadDir));
  app.use('/api', createAvatarRouter({ db, publicBaseUrl, uploadDir }));
  app.use(avatarUploadErrorHandler);

  return app;
}
