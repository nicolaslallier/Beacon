const API_BASE = "/api/minio";

async function request(path, options = {}) {
  const response = await fetch(`${API_BASE}${path}`, options);
  const contentType = response.headers.get("content-type") || "";
  const payload = contentType.includes("application/json")
    ? await response.json()
    : null;

  if (!response.ok) {
    const detail =
      payload?.detail ||
      payload?.message ||
      `Request failed with status ${response.status}`;
    throw new Error(detail);
  }

  return payload;
}

export function listBuckets() {
  return request("/buckets");
}

export function listObjects(bucket) {
  const params = new URLSearchParams();
  if (bucket) params.set("bucket", bucket);
  const query = params.toString();
  return request(`/objects${query ? `?${query}` : ""}`);
}

export function uploadObject({ bucket, objectName, file }) {
  const formData = new FormData();
  if (bucket) formData.append("bucket", bucket);
  if (objectName) formData.append("object_name", objectName);
  formData.append("file", file);

  return request("/objects", {
    method: "POST",
    body: formData,
  });
}

export function deleteObject({ bucket, objectName }) {
  const params = new URLSearchParams();
  if (bucket) params.set("bucket", bucket);
  if (objectName) params.set("object", objectName);
  const query = params.toString();

  return request(`/objects${query ? `?${query}` : ""}`, {
    method: "DELETE",
  });
}
