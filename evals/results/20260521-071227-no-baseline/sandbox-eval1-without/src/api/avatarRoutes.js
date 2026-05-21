import express from 'express';
import multer from 'multer';
import path from 'node:path';
import {
  AVATAR_MIME_EXTENSIONS,
  AvatarUploadError,
  MAX_AVATAR_BYTES,
  handleAvatarUpload
} from './avatarUploadService.js';

const defaultUploadDir = path.join(process.cwd(), 'uploads', 'avatars');

export function createAvatarRouter({
  db,
  publicBaseUrl = '/uploads/avatars',
  uploadDir = process.env.AVATAR_UPLOAD_DIR || defaultUploadDir
} = {}) {
  const router = express.Router();
  const upload = multer({
    limits: {
      fileSize: MAX_AVATAR_BYTES
    },
    storage: multer.memoryStorage(),
    fileFilter(_request, file, callback) {
      if (!AVATAR_MIME_EXTENSIONS[file.mimetype]) {
        callback(new AvatarUploadError('avatar must be a JPG, PNG, WebP, or GIF image'));
        return;
      }

      callback(null, true);
    }
  });

  router.post('/users/:userId/avatar', upload.single('avatar'), async (request, response, next) => {
    try {
      const payload = await handleAvatarUpload({
        db,
        file: request.file,
        publicBaseUrl,
        uploadDir,
        userId: request.params.userId
      });

      response.status(200).json(payload);
    } catch (error) {
      next(error);
    }
  });

  return router;
}

export function avatarUploadErrorHandler(error, _request, response, next) {
  if (!error) {
    next();
    return;
  }

  if (error instanceof multer.MulterError) {
    response.status(400).json({ error: error.message });
    return;
  }

  if (error instanceof AvatarUploadError) {
    response.status(error.statusCode).json({ error: error.message });
    return;
  }

  next(error);
}

export default createAvatarRouter;
