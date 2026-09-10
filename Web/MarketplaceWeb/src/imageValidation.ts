const acceptedImageTypes = new Set(["image/jpeg", "image/png", "image/heic"]);

export async function validateDecodableImage(file: File, maximumBytes = 10 * 1024 * 1024) {
  if (!acceptedImageTypes.has(file.type) || file.size < 1 || file.size > maximumBytes) return false;
  if (typeof createImageBitmap !== "function") return validateWithImageElement(file);
  try {
    const bitmap = await createImageBitmap(file);
    const valid = bitmap.width > 0 && bitmap.height > 0;
    bitmap.close();
    return valid;
  } catch {
    return false;
  }
}

async function validateWithImageElement(file: File) {
  if (typeof Image === "undefined" || typeof URL?.createObjectURL !== "function") return false;
  const source = URL.createObjectURL(file);
  try {
    return await new Promise<boolean>((resolve) => {
      const image = new Image();
      image.onload = () => resolve(image.naturalWidth > 0 && image.naturalHeight > 0);
      image.onerror = () => resolve(false);
      image.src = source;
    });
  } finally {
    URL.revokeObjectURL(source);
  }
}
