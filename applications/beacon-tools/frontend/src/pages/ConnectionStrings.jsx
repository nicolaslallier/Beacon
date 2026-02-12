import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  createConnectionString,
  deleteConnectionString,
  getConnectionString,
  listConnectionStrings,
  updateConnectionString,
} from "../services/toolsApi";

function ConnectionStrings({ isAuthenticated, getAccessToken }) {
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [name, setName] = useState("");
  const [host, setHost] = useState("");
  const [port, setPort] = useState("5432");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [ssl, setSsl] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [revealed, setRevealed] = useState({});

  const canSubmit = useMemo(() => {
    if (!name.trim()) return false;
    const connectionTouched =
      host.trim() ||
      port.trim() ||
      username.trim() ||
      password.trim() ||
      ssl;
    const parsedPort = Number(port);
    const portValid =
      Number.isInteger(parsedPort) && parsedPort >= 1 && parsedPort <= 65535;
    const connectionComplete =
      host.trim() && portValid && username.trim() && password.trim();
    if (editingId) {
      return connectionTouched ? connectionComplete : true;
    }
    return connectionComplete;
  }, [name, host, port, username, password, ssl, editingId]);

  const loadItems = async () => {
    if (!isAuthenticated) return;
    setLoading(true);
    setError("");
    try {
      const data = await listConnectionStrings(getAccessToken);
      setItems(data || []);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadItems();
  }, [isAuthenticated]);

  const resetForm = () => {
    setName("");
    setHost("");
    setPort("5432");
    setUsername("");
    setPassword("");
    setSsl(false);
    setEditingId(null);
  };

  const handleSubmit = async () => {
    if (!canSubmit) return;
    setBusy(true);
    setError("");
    setSuccess("");
    try {
      if (editingId) {
        const payload = {};
        if (name.trim()) payload.name = name.trim();
        const connectionTouched =
          host.trim() ||
          port.trim() ||
          username.trim() ||
          password.trim() ||
          ssl;
        if (connectionTouched) {
          payload.host = host.trim();
          payload.port = Number(port);
          payload.username = username.trim();
          payload.password = password;
          payload.ssl = ssl;
        }
        await updateConnectionString(editingId, payload, getAccessToken);
        setSuccess("Connection string updated.");
      } else {
        await createConnectionString(
          {
            name: name.trim(),
            host: host.trim(),
            port: Number(port),
            username: username.trim(),
            password,
            ssl,
          },
          getAccessToken
        );
        setSuccess("Connection string added.");
      }
      resetForm();
      await loadItems();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const parseConnectionString = (value) => {
    if (!value) return null;
    try {
      const normalized = value.startsWith("postgres://")
        ? `postgresql://${value.slice("postgres://".length)}`
        : value;
      const url = new URL(normalized);
      return {
        host: url.hostname || "",
        port: url.port || "5432",
        username: url.username ? decodeURIComponent(url.username) : "",
        password: url.password ? decodeURIComponent(url.password) : "",
        ssl: url.searchParams.get("sslmode") === "require",
      };
    } catch (err) {
      return null;
    }
  };

  const handleEdit = async (item) => {
    setEditingId(item.id);
    setName(item.name);
    setSuccess("");
    setError("");
    setBusy(true);
    try {
      const data = await getConnectionString(item.id, getAccessToken);
      const parsed = parseConnectionString(data?.connection_string);
      setHost(parsed?.host || "");
      setPort(parsed?.port || "5432");
      setUsername(parsed?.username || "");
      setPassword(parsed?.password || "");
      setSsl(Boolean(parsed?.ssl));
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const handleDelete = async (item) => {
    const confirmed = window.confirm(
      `Delete ${item.name}? This cannot be undone.`
    );
    if (!confirmed) return;
    setBusy(true);
    setError("");
    setSuccess("");
    try {
      await deleteConnectionString(item.id, getAccessToken);
      setSuccess("Connection string deleted.");
      setRevealed((prev) => {
        const next = { ...prev };
        delete next[item.id];
        return next;
      });
      await loadItems();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const handleReveal = async (item) => {
    setBusy(true);
    setError("");
    setSuccess("");
    try {
      const data = await getConnectionString(item.id, getAccessToken);
      setRevealed((prev) => ({ ...prev, [item.id]: data.connection_string }));
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  if (!isAuthenticated) {
    return (
      <section className="panel">
        <h2>Connection strings</h2>
        <p className="muted">Sign in to manage PostgreSQL connections.</p>
      </section>
    );
  }

  return (
    <section className="panel">
      <div className="panel-header">
        <div>
          <h2>Connection strings</h2>
          <p className="muted">
            Store PostgreSQL connection strings per user. Values are encrypted
            at rest.
          </p>
        </div>
        <button
          className="btn ghost"
          type="button"
          onClick={loadItems}
          disabled={loading || busy}
        >
          Refresh
        </button>
      </div>

      <div className="form-grid">
        <label className="field">
          <span>Name</span>
          <input
            placeholder="Analytics DB"
            value={name}
            onChange={(event) => setName(event.target.value)}
          />
        </label>
        <label className="field">
          <span>Host</span>
          <input
            placeholder="Database host"
            value={host}
            onChange={(event) => setHost(event.target.value)}
          />
        </label>
        <label className="field">
          <span>Port</span>
          <input
            type="number"
            min="1"
            max="65535"
            value={port}
            onChange={(event) => setPort(event.target.value)}
          />
        </label>
        <label className="field">
          <span>User name</span>
          <input
            placeholder="Database user"
            value={username}
            onChange={(event) => setUsername(event.target.value)}
          />
        </label>
        <label className="field">
          <span>Password</span>
          <input
            type="password"
            placeholder="Database password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />
        </label>
        <label className="field checkbox">
          <span>SSL required</span>
          <input
            type="checkbox"
            checked={ssl}
            onChange={(event) => setSsl(event.target.checked)}
          />
        </label>
        <div className="field actions">
          <span>{editingId ? "Update" : "Create"}</span>
          <button
            className="btn primary"
            type="button"
            onClick={handleSubmit}
            disabled={!canSubmit || busy}
          >
            {editingId ? "Save changes" : "Add connection"}
          </button>
          {editingId ? (
            <button
              className="btn ghost"
              type="button"
              onClick={resetForm}
              disabled={busy}
            >
              Cancel
            </button>
          ) : null}
        </div>
      </div>

      {loading ? (
        <p className="muted">Loading connection strings...</p>
      ) : (
        <p className="muted">
          {items.length === 0
            ? "No connection strings saved yet."
            : `${items.length} connection string(s) saved.`}
        </p>
      )}

      {error ? <p className="notice error">{error}</p> : null}
      {success ? <p className="notice success">{success}</p> : null}

      <div className="connection-list">
        <div className="connection-list-header">
          <span>Name</span>
          <span>Updated</span>
          <span>Value</span>
          <span>Actions</span>
        </div>
        {loading ? (
          <div className="connection-row muted">Loading...</div>
        ) : items.length === 0 ? (
          <div className="connection-row muted">No entries yet.</div>
        ) : (
          items.map((item) => (
            <div className="connection-row" key={item.id}>
              <span className="object-name">{item.name}</span>
              <span>
                {item.updated_at
                  ? new Date(item.updated_at).toLocaleString()
                  : "-"}
              </span>
              <span className="connection-value">
                {revealed[item.id] ? revealed[item.id] : "Hidden"}
              </span>
              <div className="row-actions">
                <Link
                  className="btn ghost"
                  to={`/connections/${item.id}`}
                  onClick={(event) => {
                    if (busy) {
                      event.preventDefault();
                    }
                  }}
                >
                  Deep dive
                </Link>
                <button
                  className="btn ghost"
                  type="button"
                  onClick={() => handleReveal(item)}
                  disabled={busy}
                >
                  Reveal
                </button>
                <button
                  className="btn"
                  type="button"
                  onClick={() => handleEdit(item)}
                  disabled={busy}
                >
                  Edit
                </button>
                <button
                  className="btn danger"
                  type="button"
                  onClick={() => handleDelete(item)}
                  disabled={busy}
                >
                  Delete
                </button>
              </div>
            </div>
          ))
        )}
      </div>
    </section>
  );
}

export default ConnectionStrings;
