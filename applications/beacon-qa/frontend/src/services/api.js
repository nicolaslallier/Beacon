const API_BASE = import.meta.env.VITE_API_URL || "/api";

async function request(path, options = {}) {
  const response = await fetch(`${API_BASE}${path}`, {
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
    ...options,
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(message || "Request failed");
  }

  if (response.status === 204) {
    return null;
  }

  const contentType = response.headers.get("content-type") || "";
  if (contentType.includes("application/json")) {
    return response.json();
  }

  const text = await response.text();
  throw new Error(text || "Unexpected non-JSON response");
}

export function getTestSuites() {
  return request("/v1/test-suites");
}

export function createTestSuite(payload) {
  return request("/v1/test-suites", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function addTestCase(suiteId, payload) {
  return request(`/v1/test-suites/${suiteId}/cases`, {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function createRun(suiteId) {
  return request("/v1/runs", {
    method: "POST",
    body: JSON.stringify({ suite_id: suiteId }),
  });
}

export function getRuns() {
  return request("/v1/runs");
}

export function getRun(runId) {
  return request(`/v1/runs/${runId}`);
}
