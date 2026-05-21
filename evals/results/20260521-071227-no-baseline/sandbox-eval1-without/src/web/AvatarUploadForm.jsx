import React, { useMemo, useState } from 'react';
import './AvatarUploadForm.css';

const MAX_AVATAR_BYTES = 5 * 1024 * 1024;
const ACCEPTED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

export default function AvatarUploadForm({
  userId,
  initialAvatarUrl = '',
  uploadUrl,
  onUploaded
}) {
  const [selectedFile, setSelectedFile] = useState(null);
  const [avatarUrl, setAvatarUrl] = useState(initialAvatarUrl);
  const [previewUrl, setPreviewUrl] = useState(initialAvatarUrl);
  const [status, setStatus] = useState('idle');
  const [error, setError] = useState('');

  const endpoint = useMemo(() => {
    if (uploadUrl) {
      return uploadUrl;
    }

    return `/api/users/${encodeURIComponent(userId)}/avatar`;
  }, [uploadUrl, userId]);

  function validateFile(file) {
    if (!file) {
      return '请选择一张头像图片。';
    }

    if (!ACCEPTED_IMAGE_TYPES.includes(file.type)) {
      return '头像仅支持 JPG、PNG、WebP 或 GIF 格式。';
    }

    if (file.size > MAX_AVATAR_BYTES) {
      return '头像文件不能超过 5MB。';
    }

    return '';
  }

  function handleFileChange(event) {
    const file = event.target.files?.[0] ?? null;
    const validationError = validateFile(file);

    setSelectedFile(file);
    setError(validationError);
    setStatus('idle');

    if (previewUrl && previewUrl.startsWith('blob:')) {
      URL.revokeObjectURL(previewUrl);
    }

    setPreviewUrl(file && !validationError ? URL.createObjectURL(file) : avatarUrl);
  }

  async function handleSubmit(event) {
    event.preventDefault();

    const validationError = validateFile(selectedFile);
    if (validationError) {
      setError(validationError);
      return;
    }

    setStatus('uploading');
    setError('');

    const body = new FormData();
    body.append('avatar', selectedFile);

    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        body
      });

      const payload = await response.json().catch(() => ({}));

      if (!response.ok) {
        throw new Error(payload.error || '头像上传失败，请稍后重试。');
      }

      setAvatarUrl(payload.avatarUrl);
      setPreviewUrl(payload.avatarUrl);
      setSelectedFile(null);
      setStatus('success');
      onUploaded?.(payload);
    } catch (uploadError) {
      setStatus('error');
      setError(uploadError.message);
    }
  }

  return (
    <form className="avatar-upload-form" onSubmit={handleSubmit}>
      <div className="avatar-upload-form__preview" aria-live="polite">
        {previewUrl ? (
          <img src={previewUrl} alt="当前头像预览" />
        ) : (
          <span>未设置头像</span>
        )}
      </div>

      <label className="avatar-upload-form__field">
        <span>上传新头像</span>
        <input
          accept={ACCEPTED_IMAGE_TYPES.join(',')}
          name="avatar"
          onChange={handleFileChange}
          type="file"
        />
      </label>

      {error ? <p className="avatar-upload-form__error">{error}</p> : null}
      {status === 'success' ? <p className="avatar-upload-form__success">头像已更新。</p> : null}

      <button disabled={status === 'uploading' || !selectedFile || Boolean(error)} type="submit">
        {status === 'uploading' ? '上传中...' : '保存头像'}
      </button>
    </form>
  );
}
