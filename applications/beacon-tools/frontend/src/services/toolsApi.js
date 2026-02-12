const API_BASE = import.meta.env.VITE_TOOLS_API_BASE || "/api/tools";

async function request(path, options = {}, getAccessToken) {
  const headers = new Headers(options.headers || {});
  if (getAccessToken) {
    const token = await getAccessToken();
    if (token) {
      const isJwt = token.split(".").length === 3;
      if (!isJwt) {
        throw new Error("Invalid access token. Please sign in again.");
      }
      headers.set("Authorization", `Bearer ${token}`);
    }
  }
  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers,
  });
  const contentType = response.headers.get("content-type") || "";
  const payload = contentType.includes("application/json")
    ? await response.json()
    : null;

  if (!response.ok) {
    const detail =
      payload?.detail ||
      payload?.message ||
      `Request failed with status ${response.status}`;
    console.error("Tools API request failed", {
      path,
      status: response.status,
      detail,
    });
    throw new Error(detail);
  }

  return payload;
}

export function listConnectionStrings(getAccessToken) {
  return request("/connection-strings", {}, getAccessToken);
}

export function createConnectionString(payload, getAccessToken) {
  return request(
    "/connection-strings",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    },
    getAccessToken
  );
}

export function updateConnectionString(id, payload, getAccessToken) {
  return request(
    `/connection-strings/${id}`,
    {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    },
    getAccessToken
  );
}

export function deleteConnectionString(id, getAccessToken) {
  return request(
    `/connection-strings/${id}`,
    { method: "DELETE" },
    getAccessToken
  );
}

export function getConnectionString(id, getAccessToken) {
  return request(`/connection-strings/${id}`, {}, getAccessToken);
}

export function listConnectionDatabases(connectionId, getAccessToken) {
  return request(
    `/connections/${connectionId}/databases`,
    {},
    getAccessToken
  );
}

export function listConnectionSchemas(connectionId, database, getAccessToken) {
  const params = new URLSearchParams({ database });
  return request(
    `/connections/${connectionId}/schemas?${params.toString()}`,
    {},
    getAccessToken
  );
}

export function listConnectionTables(
  connectionId,
  database,
  schema,
  getAccessToken
) {
  const params = new URLSearchParams({ database, schema });
  return request(
    `/connections/${connectionId}/tables?${params.toString()}`,
    {},
    getAccessToken
  );
}

export function getConnectionTableDetails(
  connectionId,
  database,
  schema,
  table,
  getAccessToken
) {
  const params = new URLSearchParams({ database, schema, table });
  return request(
    `/connections/${connectionId}/table-details?${params.toString()}`,
    {},
    getAccessToken
  );
}

export function getConnectionTableRows(
  connectionId,
  database,
  schema,
  table,
  limit,
  offset,
  getAccessToken
) {
  const params = new URLSearchParams({
    database,
    schema,
    table,
    limit: String(limit),
    offset: String(offset),
  });
  return request(
    `/connections/${connectionId}/table-rows?${params.toString()}`,
    {},
    getAccessToken
  );
}

export function startRagIngestion({ bucket, objectName, getAccessToken }) {
  console.info("Starting RAG ingestion", { bucket, objectName });
  return request(
    "/rag/ingest",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        bucket,
        object_name: objectName,
      }),
    },
    getAccessToken
  );
}

export function listRagIngestionStatus({ bucket, getAccessToken }) {
  const params = new URLSearchParams();
  if (bucket) params.set("bucket", bucket);
  const query = params.toString();
  return request(
    `/rag/ingestion-status${query ? `?${query}` : ""}`,
    {},
    getAccessToken
  );
}

export function startImageAnalysis({ bucket, objectName, getAccessToken }) {
  return request(
    "/images/analyze",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        bucket,
        object_name: objectName,
      }),
    },
    getAccessToken
  );
}

export function listImageAnalysisStatus({ bucket, getAccessToken }) {
  const params = new URLSearchParams();
  if (bucket) params.set("bucket", bucket);
  const query = params.toString();
  return request(
    `/images/analysis-status${query ? `?${query}` : ""}`,
    {},
    getAccessToken
  );
}
