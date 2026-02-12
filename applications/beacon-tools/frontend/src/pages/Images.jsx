import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { listObjects } from "../services/minioApi";
import {
  listImageAnalysisStatus,
  startImageAnalysis,
} from "../services/toolsApi";

const IMAGE_BUCKET = "images";
const IMAGE_EXTENSIONS = new Set(
  [".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"].map((e) => e.toLowerCase())
);

function isImageObject(name) {
  const i = name.lastIndexOf(".");
  if (i === -1) return false;
  return IMAGE_EXTENSIONS.has(name.slice(i).toLowerCase());
}

function formatBytes(value) {
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
}

function ImagePreview({ bucket, objectName }) {
  const [src, setSrc] = useState(null);
  const [error, setError] = useState(false);
  const cancelledRef = useRef(false);

  useEffect(() => {
    cancelledRef.current = false;
    setError(false);
    setSrc(null);

    const base = import.meta.env.VITE_MINIO_API_BASE || "/api/minio";
    const params = new URLSearchParams({ bucket, object: objectName });
    const url = `${base}/objects/download?${params.toString()}`;

    let objectURL = null;

    fetch(url, { credentials: "same-origin" })
      .then((r) => {
        if (!r.ok) throw new Error(r.statusText);
        return r.blob();
      })
      .then((blob) => {
        if (cancelledRef.current) return;
        let blobToUse = blob;
        if (!blob.type || !blob.type.startsWith("image/")) {
          const ext = (objectName || "").split(".").pop()?.toLowerCase();
          const mime =
            { jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", gif: "image/gif", webp: "image/webp", bmp: "image/bmp" }[
              ext
            ] || "image/jpeg";
          blobToUse = new Blob([blob], { type: mime });
        }
        objectURL = URL.createObjectURL(blobToUse);
        setSrc(objectURL);
      })
      .catch(() => {
        if (!cancelledRef.current) setError(true);
      });

    return () => {
      cancelledRef.current = true;
      if (objectURL) URL.revokeObjectURL(objectURL);
    };
  }, [bucket, objectName]);

  if (error) {
    return (
      <div className="image-preview image-preview-error">
        <span>Failed to load</span>
      </div>
    );
  }
  if (!src) {
    return (
      <div className="image-preview image-preview-loading">
        <span>Loading…</span>
      </div>
    );
  }
  return (
    <img
      src={src}
      alt={objectName}
      className="image-preview-img"
      loading="lazy"
    />
  );
}

function Images({
  getAccessToken,
  isAuthenticated,
}) {
  const [objects, setObjects] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [selectedNames, setSelectedNames] = useState(new Set());
  const [analyzeBusy, setAnalyzeBusy] = useState(false);
  const [statuses, setStatuses] = useState({});
  const [filterStatus, setFilterStatus] = useState("all");
  const [filterTags, setFilterTags] = useState(new Set());

  const loadObjects = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const data = await listObjects(IMAGE_BUCKET);
      const list = (data?.objects ?? []).filter((obj) =>
        isImageObject(obj.name)
      );
      setObjects(list);
    } catch (err) {
      setError(err.message || "Failed to list images.");
    } finally {
      setLoading(false);
    }
  }, []);

  const loadStatuses = useCallback(async () => {
    if (!isAuthenticated || !getAccessToken) return;
    try {
      const data = await listImageAnalysisStatus({
        bucket: IMAGE_BUCKET,
        getAccessToken,
      });
      const items = data?.items ?? [];
      const next = {};
      items.forEach((item) => {
        if (!item?.object_name) return;
        next[item.object_name] = {
          status: item.status,
          caption: item.caption,
          tags: item.tags ?? [],
          model: item.model,
          error_message: item.error_message,
          started_at: item.started_at,
          finished_at: item.finished_at,
          analyzed_by: item.analyzed_by,
        };
      });
      setStatuses(next);
    } catch (err) {
      console.warn("Failed to load image analysis statuses", err);
    }
  }, [isAuthenticated, getAccessToken]);

  useEffect(() => {
    loadObjects();
  }, [loadObjects]);

  useEffect(() => {
    loadStatuses();
    const interval = setInterval(loadStatuses, 15000);
    return () => clearInterval(interval);
  }, [loadStatuses]);

  const setStatus = (name, patch) => {
    setStatuses((prev) => ({
      ...prev,
      [name]: { ...(prev[name] || {}), ...patch },
    }));
  };

  const runAnalysis = async (objectName) => {
    setStatus(objectName, { status: "running" });
    try {
      const result = await startImageAnalysis({
        bucket: IMAGE_BUCKET,
        objectName,
        getAccessToken,
      });
      const nameAfterRename = result?.object_name || objectName;
      setStatus(nameAfterRename, {
        status: "completed",
        caption: result?.caption,
        tags: result?.tags ?? [],
        model: result?.model,
      });
      return { ok: true, result, objectName: nameAfterRename };
    } catch (err) {
      setStatus(objectName, {
        status: "failed",
        error_message: err.message,
      });
      return { ok: false, error: err };
    }
  };

  const handleAnalyzeOne = async (objectName) => {
    if (!isAuthenticated) {
      setError("Sign in to analyze images.");
      return;
    }
    setAnalyzeBusy(true);
    setError("");
    setSuccess("");
    const outcome = await runAnalysis(objectName);
    if (outcome.ok) {
      const name = outcome.objectName || objectName;
      setSuccess(
        name !== objectName
          ? `Analysis completed. Renamed to "${name}".`
          : `Analysis completed for ${objectName}.`
      );
      loadObjects();
      loadStatuses();
    } else {
      setError(outcome.error?.message || "Analysis failed.");
    }
    setAnalyzeBusy(false);
  };

  const handleAnalyzeSelected = async () => {
    if (!isAuthenticated) {
      setError("Sign in to analyze images.");
      return;
    }
    const ordered = objects
      .filter((o) => selectedNames.has(o.name))
      .map((o) => o.name);
    if (ordered.length === 0) {
      setError("Select at least one image.");
      return;
    }
    setAnalyzeBusy(true);
    setError("");
    setSuccess("");
    let okCount = 0;
    let failCount = 0;
    for (const name of ordered) {
      const outcome = await runAnalysis(name);
      if (outcome.ok) okCount += 1;
      else failCount += 1;
    }
    setSuccess(
      `Analysis finished: ${okCount} succeeded${failCount ? `, ${failCount} failed` : ""}.`
    );
    if (failCount > 0) setError("Some analyses failed. Check per-image status.");
    loadObjects();
    loadStatuses();
    setAnalyzeBusy(false);
  };

  const toggleSelection = (name) => {
    setSelectedNames((prev) => {
      const next = new Set(prev);
      if (next.has(name)) next.delete(name);
      else next.add(name);
      return next;
    });
  };

  const selectAll = () => {
    setSelectedNames(new Set(filteredObjects.map((o) => o.name)));
  };

  const clearSelection = () => {
    setSelectedNames(new Set());
  };

  const allTags = useMemo(() => {
    const tags = new Set();
    Object.values(statuses).forEach((s) => {
      (s?.tags ?? []).forEach((t) => tags.add(t));
    });
    return [...tags].sort();
  }, [statuses]);

  const filteredObjects = useMemo(() => {
    return objects.filter((obj) => {
      const s = statuses[obj.name]?.status || "idle";
      if (filterStatus === "not_analyzed") return s === "idle";
      if (filterStatus === "errors") return s === "failed" || s === "error";
      if (filterStatus === "all") {
        if (filterTags.size === 0) return true;
        const tags = statuses[obj.name]?.tags ?? [];
        return [...filterTags].some((t) => tags.includes(t));
      }
      return true;
    });
  }, [objects, statuses, filterStatus, filterTags]);

  const selectedCount = selectedNames.size;
  const allSelected =
    filteredObjects.length > 0 && selectedCount === filteredObjects.length;

  const toggleFilterTag = (tag) => {
    setFilterTags((prev) => {
      const next = new Set(prev);
      if (next.has(tag)) next.delete(tag);
      else next.add(tag);
      return next;
    });
  };

  const clearFilters = () => {
    setFilterStatus("all");
    setFilterTags(new Set());
  };

  const hasActiveFilters = filterStatus !== "all" || filterTags.size > 0;

  const renderStatusPill = (name) => {
    const s = statuses[name];
    const status = s?.status || "idle";
    if (status === "running" || status === "started") {
      return <span className="status-pill warn">Running</span>;
    }
    if (status === "completed" || status === "success") {
      return <span className="status-pill ok">Done</span>;
    }
    if (status === "failed" || status === "error") {
      return <span className="status-pill danger">Error</span>;
    }
    return <span className="status-pill muted">Idle</span>;
  };

  return (
    <>
      <section className="panel">
        <div className="panel-header">
          <div>
            <h2>Images (bucket: {IMAGE_BUCKET})</h2>
            <p className="muted">
              View and analyze images with AI. Select images and run analysis to
              get captions and tags.
            </p>
          </div>
          <button
            type="button"
            className="btn ghost"
            onClick={loadObjects}
            disabled={loading}
          >
            Refresh
          </button>
        </div>

        {error ? <p className="notice error">{error}</p> : null}
        {success ? <p className="notice success">{success}</p> : null}

        <div className="image-filters">
          <div className="filter-group">
            <span className="filter-label">Show</span>
            <select
              value={filterStatus}
              onChange={(e) => setFilterStatus(e.target.value)}
              className="filter-select"
              aria-label="Filter by status"
            >
              <option value="all">All images</option>
              <option value="not_analyzed">Not analyzed</option>
              <option value="errors">Errors only</option>
            </select>
          </div>
          {allTags.length > 0 ? (
            <div className="filter-group filter-tags">
              <span className="filter-label">Tag</span>
              <div className="filter-tag-list">
                {allTags.map((tag) => (
                  <button
                    key={tag}
                    type="button"
                    className={`tag-pill filter-tag ${filterTags.has(tag) ? "active" : ""}`}
                    onClick={() => toggleFilterTag(tag)}
                  >
                    {tag}
                  </button>
                ))}
              </div>
            </div>
          ) : null}
          {hasActiveFilters ? (
            <button
              type="button"
              className="btn ghost"
              onClick={clearFilters}
            >
              Clear filters
            </button>
          ) : null}
        </div>
        <p className="muted filter-summary">
          Showing {filteredObjects.length} of {objects.length} images
          {hasActiveFilters ? " (filtered)" : ""}.
        </p>

        <div className="object-list-actions">
          <div className="selection-summary">
            <span className="muted">{selectedCount} selected</span>
          </div>
          <div className="row-actions">
            <button
              type="button"
              className="btn ghost"
              onClick={selectAll}
              disabled={filteredObjects.length === 0 || analyzeBusy}
            >
              Select all
            </button>
            <button
              type="button"
              className="btn ghost"
              onClick={clearSelection}
              disabled={selectedCount === 0 || analyzeBusy}
            >
              Clear
            </button>
            <button
              type="button"
              className="btn primary"
              onClick={handleAnalyzeSelected}
              disabled={selectedCount === 0 || analyzeBusy || !isAuthenticated}
            >
              Analyze selected ({selectedCount})
            </button>
          </div>
        </div>

        {loading ? (
          <p className="muted">Loading images…</p>
        ) : objects.length === 0 ? (
          <p className="muted">
            No images in bucket &quot;{IMAGE_BUCKET}&quot;. Upload images or
            choose another bucket.
          </p>
        ) : filteredObjects.length === 0 ? (
          <p className="muted">
            No images match the current filters. Try changing or clearing filters.
          </p>
        ) : (
          <div className="image-gallery">
            {filteredObjects.map((item) => (
              <div className="image-card" key={item.name}>
                <div className="image-card-preview">
                  <ImagePreview
                    bucket={IMAGE_BUCKET}
                    objectName={item.name}
                  />
                </div>
                <div className="image-card-body">
                  <label className="image-card-select">
                    <input
                      type="checkbox"
                      checked={selectedNames.has(item.name)}
                      onChange={() => toggleSelection(item.name)}
                      disabled={analyzeBusy}
                    />
                    <span className="image-card-name" title={item.name}>
                      {item.name}
                    </span>
                  </label>
                  <div className="image-card-meta">
                    <span>{formatBytes(item.size)}</span>
                    <span>{renderStatusPill(item.name)}</span>
                  </div>
                  {statuses[item.name]?.caption ? (
                    <p className="image-card-caption muted">
                      {statuses[item.name].caption}
                    </p>
                  ) : null}
                  {statuses[item.name]?.tags?.length > 0 ? (
                    <div className="image-card-tags">
                      {(statuses[item.name].tags || []).map((tag, i) => (
                        <span key={i} className="tag-pill">
                          {tag}
                        </span>
                      ))}
                    </div>
                  ) : null}
                  <div className="row-actions">
                    <button
                      type="button"
                      className="btn primary"
                      onClick={() => handleAnalyzeOne(item.name)}
                      disabled={analyzeBusy || !isAuthenticated}
                    >
                      Analyze
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
    </>
  );
}

export default Images;
