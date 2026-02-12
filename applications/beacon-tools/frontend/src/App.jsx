import { useEffect, useMemo, useRef, useState } from "react";
import Keycloak from "keycloak-js";
import { BrowserRouter, NavLink, Route, Routes } from "react-router-dom";
import {
  deleteObject,
  listBuckets,
  listObjects,
  uploadObject,
} from "./services/minioApi";
import { listRagIngestionStatus, startRagIngestion } from "./services/toolsApi";
import ConnectionStrings from "./pages/ConnectionStrings";
import Images from "./pages/Images";
import PostgreSQLConnectionDetail from "./pages/PostgreSQLConnectionDetail";

const tools = [
  {
    name: "Workspace Hub",
    description: "Launch and manage Beacon utility workflows.",
    status: "Coming soon",
  },
  {
    name: "Runbooks",
    description: "Track operational procedures and quick actions.",
    status: "Coming soon",
  },
  {
    name: "Diagnostics",
    description: "Check health for services and integrations.",
    status: "Coming soon",
  },
];

const postgresDatabases = [
  {
    name: "Vector DB",
    host: "vectordb.beacon.famillelallier.net",
  },
  {
    name: "PostgreSQL",
    host: "postgresql.beacon.famillelallier.net",
  },
];

function ToolsHome({
  buckets,
  bucketName,
  setBucketName,
  objects,
  loadingBuckets,
  loadingObjects,
  busyAction,
  error,
  success,
  objectName,
  setObjectName,
  file,
  setFile,
  fileInputKey,
  loadObjects,
  handleUpload,
  handleDelete,
  handleIngest,
  handleIngestSelected,
  ingestBusy,
  formatBytes,
  selectedObjects,
  toggleObjectSelection,
  selectAllObjects,
  clearObjectSelection,
  ingestStatuses,
  sortKey,
  sortDir,
  handleSort,
}) {
  const selectedCount = selectedObjects.size;
  const allSelected =
    objects.length > 0 && selectedCount === objects.length;

  const renderStatusPill = (name) => {
    const statusEntry = ingestStatuses[name];
    const status = statusEntry?.status || "idle";
    if (status === "queued") {
      return <span className="status-pill muted">Queued</span>;
    }
    if (status === "running" || status === "started") {
      return <span className="status-pill warn">Running</span>;
    }
    if (status === "success" || status === "completed") {
      const chunks = statusEntry?.chunks;
      return (
        <span className="status-pill ok">
          {typeof chunks === "number" ? `Done (${chunks})` : "Done"}
        </span>
      );
    }
    if (status === "error" || status === "failed") {
      return <span className="status-pill danger">Error</span>;
    }
    return <span className="status-pill muted">Idle</span>;
  };

  const getSortLabel = (label, key) => {
    if (sortKey !== key) return label;
    return `${label} ${sortDir === "asc" ? "▲" : "▼"}`;
  };

  return (
    <>
      <section className="panel">
        <h2>Available tools</h2>
        <div className="grid">
          {tools.map((tool) => (
            <div className="card" key={tool.name}>
              <div>
                <h3>{tool.name}</h3>
                <p>{tool.description}</p>
              </div>
              <span className="status-pill muted">{tool.status}</span>
            </div>
          ))}
        </div>
      </section>

      <section className="panel">
        <h2>PostgreSQL databases</h2>
        <ul className="list">
          {postgresDatabases.map((database) => (
            <li key={database.host}>
              {database.name}: {database.host}
            </li>
          ))}
        </ul>
      </section>

      <section className="panel">
        <div className="panel-header">
          <div>
            <h2>MinIO storage</h2>
            <p className="muted">
              Upload and manage files in the beacon-minio cluster.
            </p>
          </div>
          <button
            className="btn ghost"
            type="button"
            onClick={() => loadObjects(bucketName)}
            disabled={loadingObjects}
          >
            Refresh
          </button>
        </div>

        <div className="form-grid">
          <label className="field">
            <span>Bucket</span>
            <input
              list="minio-buckets"
              placeholder="Bucket name"
              value={bucketName}
              onChange={(event) => setBucketName(event.target.value)}
            />
            <span className="helper">
              If the list is empty, type the bucket name manually.
            </span>
            <datalist id="minio-buckets">
              {buckets.map((bucket) => (
                <option key={bucket.name} value={bucket.name} />
              ))}
            </datalist>
          </label>
          <label className="field">
            <span>Object name (optional)</span>
            <input
              placeholder="folder/file.txt"
              value={objectName}
              onChange={(event) => setObjectName(event.target.value)}
            />
          </label>
          <label className="field">
            <span>File</span>
            <input
              key={fileInputKey}
              type="file"
              onChange={(event) => setFile(event.target.files?.[0] ?? null)}
            />
          </label>
          <div className="field actions">
            <span>Upload</span>
            <button
              className="btn primary"
              type="button"
              onClick={handleUpload}
              disabled={busyAction || loadingBuckets}
            >
              Upload file
            </button>
          </div>
        </div>

        {loadingBuckets ? (
          <p className="muted">Loading buckets...</p>
        ) : (
          <p className="muted">
            {buckets.length === 0
              ? "No buckets discovered. Type one above to continue."
              : `${buckets.length} bucket(s) found.`}
          </p>
        )}

        {error ? <p className="notice error">{error}</p> : null}
        {success ? <p className="notice success">{success}</p> : null}

        <div className="object-list-actions">
          <div className="selection-summary">
            <span className="muted">{selectedCount} selected</span>
          </div>
          <div className="row-actions">
            <button
              className="btn ghost"
              type="button"
              onClick={selectAllObjects}
              disabled={objects.length === 0 || busyAction || ingestBusy}
            >
              Select all
            </button>
            <button
              className="btn ghost"
              type="button"
              onClick={clearObjectSelection}
              disabled={selectedCount === 0 || busyAction || ingestBusy}
            >
              Clear
            </button>
            <button
              className="btn primary"
              type="button"
              onClick={handleIngestSelected}
              disabled={selectedCount === 0 || busyAction || ingestBusy}
            >
              Start RAG for selected ({selectedCount})
            </button>
          </div>
        </div>

        <div className="object-list">
          <div className="object-list-header">
            <span>
              <input
                aria-label="Select all objects"
                type="checkbox"
                checked={allSelected}
                onChange={(event) =>
                  event.target.checked
                    ? selectAllObjects()
                    : clearObjectSelection()
                }
                disabled={objects.length === 0 || busyAction || ingestBusy}
              />
            </span>
            <button
              type="button"
              className="sort-button"
              onClick={() => handleSort("object")}
              disabled={objects.length === 0}
            >
              {getSortLabel("Object", "object")}
            </button>
            <button
              type="button"
              className="sort-button"
              onClick={() => handleSort("size")}
              disabled={objects.length === 0}
            >
              {getSortLabel("Size", "size")}
            </button>
            <button
              type="button"
              className="sort-button"
              onClick={() => handleSort("modified")}
              disabled={objects.length === 0}
            >
              {getSortLabel("Last modified", "modified")}
            </button>
            <button
              type="button"
              className="sort-button"
              onClick={() => handleSort("status")}
              disabled={objects.length === 0}
            >
              {getSortLabel("Status", "status")}
            </button>
            <span>Actions</span>
          </div>
          {loadingObjects ? (
            <div className="object-row muted">Loading objects...</div>
          ) : objects.length === 0 ? (
            <div className="object-row muted">No objects to display.</div>
          ) : (
            objects.map((item) => (
              <div className="object-row" key={item.name}>
                <span>
                  <input
                    aria-label={`Select ${item.name}`}
                    type="checkbox"
                    checked={selectedObjects.has(item.name)}
                    onChange={() => toggleObjectSelection(item.name)}
                    disabled={busyAction || ingestBusy}
                  />
                </span>
                <span className="object-name">{item.name}</span>
                <span>{formatBytes(item.size)}</span>
                <span>
                  {item.last_modified
                    ? new Date(item.last_modified).toLocaleString()
                    : "-"}
                </span>
                <span>{renderStatusPill(item.name)}</span>
                <div className="row-actions">
                  <button
                    className="btn primary"
                    type="button"
                    onClick={() => handleIngest(item.name)}
                    disabled={busyAction || ingestBusy}
                  >
                    Start RAG
                  </button>
                  <button
                    className="btn danger"
                    type="button"
                    onClick={() => handleDelete(item.name)}
                    disabled={busyAction}
                  >
                    Delete
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </section>

      <section className="panel">
        <h2>Next steps</h2>
        <ul className="list">
          <li>Spin up the first serverless Python service.</li>
          <li>Connect API routes behind NGINX.</li>
          <li>Add authentication and role-based access.</li>
        </ul>
      </section>
    </>
  );
}

function App() {
  const [buckets, setBuckets] = useState([]);
  const [bucketName, setBucketName] = useState("");
  const [objects, setObjects] = useState([]);
  const [loadingBuckets, setLoadingBuckets] = useState(false);
  const [loadingObjects, setLoadingObjects] = useState(false);
  const [busyAction, setBusyAction] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [objectName, setObjectName] = useState("");
  const [file, setFile] = useState(null);
  const [fileInputKey, setFileInputKey] = useState(0);
  const [ingestBusy, setIngestBusy] = useState(false);
  const [selectedObjects, setSelectedObjects] = useState(new Set());
  const [ingestStatuses, setIngestStatuses] = useState({});
  const [sortKey, setSortKey] = useState("object");
  const [sortDir, setSortDir] = useState("asc");
  const [keycloak, setKeycloak] = useState(null);
  const [authReady, setAuthReady] = useState(false);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [authError, setAuthError] = useState("");

  const formatBytes = (value) => {
    if (value === undefined || value === null) return "-";
    const units = ["B", "KB", "MB", "GB", "TB"];
    let size = value;
    let unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }
    const precision = size >= 10 || unitIndex === 0 ? 0 : 1;
    return `${size.toFixed(precision)} ${units[unitIndex]}`;
  };

  const handleSort = (key) => {
    setSortKey((prev) => {
      if (prev === key) {
        setSortDir((dir) => (dir === "asc" ? "desc" : "asc"));
        return prev;
      }
      setSortDir("asc");
      return key;
    });
  };

  const statusOrder = {
    idle: 0,
    queued: 1,
    running: 2,
    started: 2,
    success: 3,
    completed: 3,
    error: 4,
    failed: 4,
  };

  const sortedObjects = useMemo(() => {
    const list = [...objects];
    const factor = sortDir === "asc" ? 1 : -1;
    list.sort((a, b) => {
      if (sortKey === "object") {
        return a.name.localeCompare(b.name) * factor;
      }
      if (sortKey === "size") {
        return ((a.size || 0) - (b.size || 0)) * factor;
      }
      if (sortKey === "modified") {
        const aTime = a.last_modified
          ? new Date(a.last_modified).getTime()
          : 0;
        const bTime = b.last_modified
          ? new Date(b.last_modified).getTime()
          : 0;
        return (aTime - bTime) * factor;
      }
      if (sortKey === "status") {
        const aStatus = ingestStatuses[a.name]?.status || "idle";
        const bStatus = ingestStatuses[b.name]?.status || "idle";
        const aValue = statusOrder[aStatus] ?? 0;
        const bValue = statusOrder[bStatus] ?? 0;
        if (aValue !== bValue) return (aValue - bValue) * factor;
        return a.name.localeCompare(b.name) * factor;
      }
      return 0;
    });
    return list;
  }, [objects, sortDir, sortKey, ingestStatuses]);

  const loadBuckets = async () => {
    setLoadingBuckets(true);
    setError("");
    try {
      const data = await listBuckets();
      const bucketList = data?.buckets ?? [];
      setBuckets(bucketList);
      if (!bucketName && bucketList.length > 0) {
        setBucketName(bucketList[0].name);
      }
    } catch (err) {
      setError(err.message);
    } finally {
      setLoadingBuckets(false);
    }
  };

  const loadObjects = async (bucket) => {
    if (!bucket) {
      setObjects([]);
      setError("Choose a bucket before refreshing objects.");
      return;
    }
    setLoadingObjects(true);
    setError("");
    try {
      const data = await listObjects(bucket);
      const objectList = data?.objects ?? [];
      setObjects(objectList);
      setSelectedObjects((prev) => {
        if (prev.size === 0) return prev;
        const next = new Set();
        objectList.forEach((item) => {
          if (prev.has(item.name)) next.add(item.name);
        });
        return next;
      });
      setIngestStatuses((prev) => {
        const next = {};
        objectList.forEach((item) => {
          if (prev[item.name]) {
            next[item.name] = prev[item.name];
          }
        });
        return next;
      });
    } catch (err) {
      setError(err.message);
    } finally {
      setLoadingObjects(false);
    }
  };

  const loadIngestionStatuses = async (bucket) => {
    if (!bucket) {
      setIngestStatuses({});
      return;
    }
    try {
      const data = await listRagIngestionStatus({
        bucket,
        getAccessToken,
      });
      const items = data?.items ?? [];
      const next = {};
      items.forEach((item) => {
        if (!item?.object_name) return;
        next[item.object_name] = {
          status: item.status,
          chunks: item.chunks,
          error: item.error_message,
          started_at: item.started_at,
          finished_at: item.finished_at,
          standard_id: item.standard_id,
          ingested_by: item.ingested_by,
        };
      });
      setIngestStatuses(next);
    } catch (err) {
      setError(err.message);
    }
  };

  useEffect(() => {
    const savedBucket = window.localStorage.getItem("beaconToolsBucket");
    if (savedBucket && !bucketName) {
      setBucketName(savedBucket);
    }
    loadBuckets();
  }, []);

  useEffect(() => {
    setSelectedObjects(new Set());
    setIngestStatuses({});
    loadObjects(bucketName);
  }, [bucketName]);

  useEffect(() => {
    if (bucketName) {
      window.localStorage.setItem("beaconToolsBucket", bucketName);
    }
  }, [bucketName]);

  const handleUpload = async () => {
    setError("");
    setSuccess("");
    if (!bucketName) {
      setError("Bucket is required before uploading.");
      return;
    }
    if (!file) {
      setError("Select a file to upload.");
      return;
    }
    setBusyAction(true);
    try {
      await uploadObject({
        bucket: bucketName,
        objectName: objectName.trim(),
        file,
      });
      setSuccess("Upload complete.");
      setObjectName("");
      setFile(null);
      setFileInputKey((prev) => prev + 1);
      await loadObjects(bucketName);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusyAction(false);
    }
  };

  const handleDelete = async (name) => {
    if (!bucketName) {
      setError("Bucket is required before deleting.");
      return;
    }
    if (!name) return;
    const confirmed = window.confirm(
      `Delete ${name} from ${bucketName}? This cannot be undone.`
    );
    if (!confirmed) return;
    setBusyAction(true);
    setError("");
    setSuccess("");
    try {
      await deleteObject({ bucket: bucketName, objectName: name });
      setSelectedObjects((prev) => {
        if (!prev.has(name)) return prev;
        const next = new Set(prev);
        next.delete(name);
        return next;
      });
      setIngestStatuses((prev) => {
        if (!prev[name]) return prev;
        const next = { ...prev };
        delete next[name];
        return next;
      });
      setSuccess("Object deleted.");
      await loadObjects(bucketName);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusyAction(false);
    }
  };

  const setIngestStatus = (name, patch) => {
    setIngestStatuses((prev) => ({
      ...prev,
      [name]: {
        ...(prev[name] || {}),
        ...patch,
      },
    }));
  };

  const ingestObject = async (name) => {
    setIngestStatus(name, { status: "running", error: null });
    try {
      const result = await startRagIngestion({
        bucket: bucketName,
        objectName: name,
        getAccessToken,
      });
      setIngestStatus(name, {
        status: "success",
        chunks: result?.chunks,
        standardId: result?.standard_id,
      });
      return { ok: true, result };
    } catch (err) {
      setIngestStatus(name, { status: "error", error: err.message });
      return { ok: false, error: err };
    }
  };

  const handleIngest = async (name) => {
    if (!bucketName) {
      setError("Bucket is required before ingestion.");
      return;
    }
    if (!name) return;
    setIngestBusy(true);
    setError("");
    setSuccess("");
    const outcome = await ingestObject(name);
    if (outcome.ok) {
      setSuccess(`RAG ingestion completed for ${name}.`);
    } else {
      setError(outcome.error?.message || "RAG ingestion failed.");
    }
    setIngestBusy(false);
  };

  const handleIngestSelected = async () => {
    if (!bucketName) {
      setError("Bucket is required before ingestion.");
      return;
    }
    const orderedSelection = objects
      .filter((item) => selectedObjects.has(item.name))
      .map((item) => item.name);
    if (orderedSelection.length === 0) {
      setError("Select at least one object to ingest.");
      return;
    }
    setIngestBusy(true);
    setError("");
    setSuccess("");
    setIngestStatuses((prev) => {
      const next = { ...prev };
      orderedSelection.forEach((name) => {
        next[name] = { ...(next[name] || {}), status: "queued", error: null };
      });
      return next;
    });
    let successCount = 0;
    let errorCount = 0;
    for (const name of orderedSelection) {
      const outcome = await ingestObject(name);
      if (outcome.ok) {
        successCount += 1;
      } else {
        errorCount += 1;
      }
    }
    setIngestBusy(false);
    setSuccess(
      `RAG ingestion finished: ${successCount} succeeded, ${errorCount} failed.`
    );
    if (errorCount > 0) {
      setError("Some ingestions failed. Check per-file status.");
    }
  };

  const toggleObjectSelection = (name) => {
    setSelectedObjects((prev) => {
      const next = new Set(prev);
      if (next.has(name)) {
        next.delete(name);
      } else {
        next.add(name);
      }
      return next;
    });
  };

  const selectAllObjects = () => {
    setSelectedObjects(new Set(objects.map((item) => item.name)));
  };

  const clearObjectSelection = () => {
    setSelectedObjects(new Set());
  };

  const authInitRef = useRef(false);

  useEffect(() => {
    if (authInitRef.current) return;
    authInitRef.current = true;
    const url = import.meta.env.VITE_KEYCLOAK_URL;
    const realm = import.meta.env.VITE_KEYCLOAK_REALM;
    const clientId = import.meta.env.VITE_KEYCLOAK_CLIENT_ID;
    if (!url || !realm || !clientId) {
      setAuthReady(true);
      return;
    }
    const client = new Keycloak({ url, realm, clientId });
    client
      .init({
        onLoad: "check-sso",
        pkceMethod: "S256",
        silentCheckSsoRedirectUri: `${window.location.origin}/silent-check-sso.html`,
      })
      .then((authenticated) => {
        setKeycloak(client);
        setIsAuthenticated(authenticated);
        setAuthReady(true);
      })
      .catch((err) => {
        setAuthError(`Auth init failed: ${err?.message || err}`);
        setAuthReady(true);
      });
  }, []);

  const getAccessToken = useMemo(() => {
    return async () => {
      if (!keycloak) return null;
      try {
        await keycloak.updateToken(30);
      } catch (err) {
        setAuthError("Session expired. Please sign in again.");
        setIsAuthenticated(false);
        return null;
      }
      return keycloak.token;
    };
  }, [keycloak]);

  useEffect(() => {
    if (!bucketName) return undefined;
    if (!keycloak || !isAuthenticated) return undefined;
    loadIngestionStatuses(bucketName);
    const intervalId = window.setInterval(() => {
      loadIngestionStatuses(bucketName);
    }, 300000);
    return () => window.clearInterval(intervalId);
  }, [bucketName, getAccessToken, isAuthenticated, keycloak]);

  const handleLogin = () => {
    if (!keycloak) return;
    keycloak.login();
  };

  const handleLogout = () => {
    if (!keycloak) return;
    keycloak.logout();
  };

  const userLabel =
    keycloak?.tokenParsed?.preferred_username ||
    keycloak?.tokenParsed?.email ||
    "Signed in";

  return (
    <div className="app">
      <BrowserRouter
        future={{
          v7_startTransition: true,
          v7_relativeSplatPath: true,
        }}
      >
        <header className="hero">
          <div>
            <p className="eyebrow">Beacon Platform</p>
            <h1>Tools</h1>
            <p className="subtitle">
              Your control panel for Beacon utilities and automations.
            </p>
            <nav className="nav">
              <NavLink to="/" end className="nav-link">
                Overview
              </NavLink>
              <NavLink to="/images" className="nav-link">
                Images
              </NavLink>
              <NavLink to="/connections" className="nav-link">
                Connection strings
              </NavLink>
            </nav>
          </div>
          <div className="hero-card">
            <h2>Quick status</h2>
            <div className="status-row">
              <span>Frontend</span>
              <span className="status-pill ok">Online</span>
            </div>
            <div className="status-row">
              <span>Backend</span>
              <span className="status-pill muted">Planned</span>
            </div>
            <div className="status-row">
              <span>Auth</span>
              <span className={`status-pill ${authReady ? "ok" : "muted"}`}>
                {authReady ? "Ready" : "Loading"}
              </span>
            </div>
            <div className="auth-row">
              {isAuthenticated ? (
                <>
                  <span className="muted">{userLabel}</span>
                  <button className="btn ghost" onClick={handleLogout}>
                    Sign out
                  </button>
                </>
              ) : (
                <button
                  className="btn primary"
                  onClick={handleLogin}
                  disabled={!authReady || !keycloak}
                >
                  Sign in
                </button>
              )}
            </div>
            {authError ? <p className="notice error">{authError}</p> : null}
          </div>
        </header>

        <Routes>
          <Route
            path="/"
            element={
              <ToolsHome
                buckets={buckets}
                bucketName={bucketName}
                setBucketName={setBucketName}
                objects={sortedObjects}
                loadingBuckets={loadingBuckets}
                loadingObjects={loadingObjects}
                busyAction={busyAction}
                error={error}
                success={success}
                objectName={objectName}
                setObjectName={setObjectName}
                file={file}
                setFile={setFile}
                fileInputKey={fileInputKey}
                loadObjects={loadObjects}
                handleUpload={handleUpload}
                handleDelete={handleDelete}
                handleIngest={handleIngest}
                handleIngestSelected={handleIngestSelected}
                ingestBusy={ingestBusy}
                formatBytes={formatBytes}
                selectedObjects={selectedObjects}
                toggleObjectSelection={toggleObjectSelection}
                selectAllObjects={selectAllObjects}
                clearObjectSelection={clearObjectSelection}
                ingestStatuses={ingestStatuses}
                sortKey={sortKey}
                sortDir={sortDir}
                handleSort={handleSort}
              />
            }
          />
          <Route
            path="/images"
            element={
              <Images
                getAccessToken={getAccessToken}
                isAuthenticated={isAuthenticated}
              />
            }
          />
          <Route
            path="/connections"
            element={
              <ConnectionStrings
                isAuthenticated={isAuthenticated}
                getAccessToken={getAccessToken}
              />
            }
          />
          <Route
            path="/connections/:connectionId"
            element={
              <PostgreSQLConnectionDetail
                isAuthenticated={isAuthenticated}
                getAccessToken={getAccessToken}
              />
            }
          />
        </Routes>
      </BrowserRouter>
    </div>
  );
}

export default App;
