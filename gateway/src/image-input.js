import { Fault } from './security.js';

export const imageConstraints = Object.freeze({
  mimeTypes: ['image/png', 'image/jpeg', 'image/gif', 'image/webp'],
  maxCount: 5, maxBytesPerAttachment: 5 * 1024 * 1024, maxTotalBytes: 10 * 1024 * 1024,
});
export const imageRequestBytes = 15 * 1024 * 1024;

function signature(bytes, mime) {
  if (mime === 'image/png') return bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  if (mime === 'image/jpeg') return bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
  if (mime === 'image/gif') return ['GIF87a', 'GIF89a'].includes(bytes.subarray(0, 6).toString('ascii'));
  return bytes.length >= 12 && bytes.subarray(0, 4).toString('ascii') === 'RIFF' && bytes.subarray(8, 12).toString('ascii') === 'WEBP';
}

export function validatePromptParts(parts) {
  if (!Array.isArray(parts) || !parts.length || parts.length > 64) throw new Fault(400, 'invalid_prompt_parts');
  const images = [];
  const texts = [];
  const normalized = [];
  let imageBytes = 0;
  for (const part of parts) {
    if (part?.type === 'text' && typeof part.text === 'string') {
      texts.push(part.text);
      normalized.push({ type: 'text', text: part.text });
      continue;
    }
    if (part?.type !== 'file' || !imageConstraints.mimeTypes.includes(part.mime) || typeof part.url !== 'string') throw new Fault(400, 'image_attachments_only');
    if (images.length >= imageConstraints.maxCount) throw new Fault(413, 'attachment_count_limit');
    if (part.filename !== undefined && (typeof part.filename !== 'string' || part.filename.length > 255 || /[\x00-\x1f\x7f]/.test(part.filename))) throw new Fault(400, 'invalid_attachment_name');
    const prefix = `data:${part.mime};base64,`;
    if (!part.url.startsWith(prefix)) throw new Fault(400, 'inline_image_required');
    const data = part.url.slice(prefix.length);
    if (data.length > 4 * Math.ceil(imageConstraints.maxBytesPerAttachment / 3)) throw new Fault(413, 'attachment_size_limit');
    if (!data.length || data.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(data)) throw new Fault(400, 'invalid_image_encoding');
    const bytes = Buffer.from(data, 'base64');
    try {
      if (bytes.length > imageConstraints.maxBytesPerAttachment) throw new Fault(413, 'attachment_size_limit');
      if (bytes.toString('base64') !== data || !signature(bytes, part.mime)) throw new Fault(400, 'invalid_image_encoding');
      imageBytes += bytes.length;
      if (imageBytes > imageConstraints.maxTotalBytes) throw new Fault(413, 'attachment_total_limit');
    } finally { bytes.fill(0); }
    images.push({ mime: part.mime, data, url: part.url });
    normalized.push({ type: 'file', mime: part.mime, filename: part.filename || 'Image', url: part.url });
  }
  const text = texts.join('\n');
  if ((!text.trim() && !images.length) || Buffer.byteLength(text) > 128 * 1024) throw new Fault(400, 'invalid_prompt');
  return { text, images, parts: normalized, imageBytes };
}
