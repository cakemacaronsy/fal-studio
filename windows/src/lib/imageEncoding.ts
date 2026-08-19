// Port of Sources/Services/ImageEncoding.swift — prepares dropped reference
// images for upload: downscale to longest edge 2048 and re-encode (JPEG, or
// PNG when the image actually uses transparency), so a 12 MP photo doesn't
// become a 15 MB base64 request body.

export interface EncodedImage {
  bytes: Uint8Array;
  mime: string; // image/jpeg or image/png
}

export async function encodeForUpload(
  source: Blob,
  maxPixel = 2048
): Promise<EncodedImage> {
  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(source);
  } catch {
    throw new Error("Could not read image");
  }
  const scale = Math.min(1, maxPixel / Math.max(bitmap.width, bitmap.height));
  const width = Math.max(1, Math.round(bitmap.width * scale));
  const height = Math.max(1, Math.round(bitmap.height * scale));

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d")!;
  ctx.drawImage(bitmap, 0, 0, width, height);
  bitmap.close();

  // Detect real transparency by sampling the alpha channel.
  const data = ctx.getImageData(0, 0, width, height).data;
  let hasAlpha = false;
  const stride = Math.max(4, Math.floor(data.length / 4 / 4096) * 4);
  for (let i = 3; i < data.length; i += stride) {
    if (data[i] < 255) {
      hasAlpha = true;
      break;
    }
  }

  const mime = hasAlpha ? "image/png" : "image/jpeg";
  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, mime, hasAlpha ? undefined : 0.9)
  );
  if (!blob) throw new Error("Could not encode image");
  return { bytes: new Uint8Array(await blob.arrayBuffer()), mime };
}

export function mimeForBytes(bytes: Uint8Array): string {
  // PNG magic number: 0x89 'P' 'N' 'G'
  return bytes.length >= 4 &&
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47
    ? "image/png"
    : "image/jpeg";
}

export function base64Encode(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

export function base64Decode(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export function dataURI(bytes: Uint8Array, mime?: string): string {
  return `data:${mime ?? mimeForBytes(bytes)};base64,${base64Encode(bytes)}`;
}

export async function pixelSize(
  bytes: Uint8Array
): Promise<{ width: number; height: number } | null> {
  try {
    const bitmap = await createImageBitmap(
      new Blob([bytes.slice().buffer], { type: mimeForBytes(bytes) })
    );
    const size = { width: bitmap.width, height: bitmap.height };
    bitmap.close();
    return size;
  } catch {
    return null;
  }
}

export function bytesToBlob(bytes: Uint8Array, mime?: string): Blob {
  return new Blob([bytes.slice().buffer], { type: mime ?? mimeForBytes(bytes) });
}

/** Small JPEG thumbnail for gallery cards (longest edge `maxPixel`). */
export async function imageThumbnail(
  bytes: Uint8Array,
  maxPixel = 512
): Promise<Uint8Array | null> {
  try {
    const bitmap = await createImageBitmap(bytesToBlob(bytes));
    const scale = Math.min(1, maxPixel / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    const ctx = canvas.getContext("2d")!;
    ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    bitmap.close();
    const blob = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, "image/jpeg", 0.8)
    );
    return blob ? new Uint8Array(await blob.arrayBuffer()) : null;
  } catch {
    return null;
  }
}

/** First-frame JPEG thumbnail for a video the webview can play. */
export function videoThumbnail(url: string): Promise<Uint8Array | null> {
  return new Promise((resolve) => {
    const video = document.createElement("video");
    video.muted = true;
    video.preload = "auto";
    video.src = url;
    const fail = () => resolve(null);
    const timer = setTimeout(fail, 8000);
    video.addEventListener("error", () => {
      clearTimeout(timer);
      fail();
    });
    video.addEventListener("loadeddata", () => {
      video.currentTime = Math.min(0.1, video.duration || 0);
    });
    video.addEventListener("seeked", async () => {
      clearTimeout(timer);
      try {
        const canvas = document.createElement("canvas");
        const scale = Math.min(1, 512 / Math.max(video.videoWidth, video.videoHeight));
        canvas.width = Math.max(1, Math.round(video.videoWidth * scale));
        canvas.height = Math.max(1, Math.round(video.videoHeight * scale));
        canvas.getContext("2d")!.drawImage(video, 0, 0, canvas.width, canvas.height);
        const blob = await new Promise<Blob | null>((r) =>
          canvas.toBlob(r, "image/jpeg", 0.8)
        );
        resolve(blob ? new Uint8Array(await blob.arrayBuffer()) : null);
      } catch {
        resolve(null);
      }
    });
  });
}
