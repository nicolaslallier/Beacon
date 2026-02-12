import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import {
  getConnectionString,
  getConnectionTableDetails,
  getConnectionTableRows,
  listConnectionDatabases,
  listConnectionSchemas,
  listConnectionTables,
} from "../services/toolsApi";

function parseConnectionString(value) {
  if (!value) return null;
  try {
    const normalized = value.startsWith("postgres://")
      ? `postgresql://${value.slice("postgres://".length)}`
      : value;
    const url = new URL(normalized);
    const params = {};
    url.searchParams.forEach((paramValue, key) => {
      if (params[key]) {
        const existing = params[key];
        params[key] = Array.isArray(existing)
          ? [...existing, paramValue]
          : [existing, paramValue];
      } else {
        params[key] = paramValue;
      }
    });

    return {
      host: url.hostname || "-",
      port: url.port || "-",
      database: url.pathname ? url.pathname.replace(/^\/+/, "") || "-" : "-",
      user: url.username ? decodeURIComponent(url.username) : "-",
      password: url.password ? "Set" : "-",
      sslmode: url.searchParams.get("sslmode") || "-",
      params,
    };
  } catch (err) {
    return { error: err?.message || "Unable to parse connection string." };
  }
}

function PostgreSQLConnectionDetail({ isAuthenticated, getAccessToken }) {
  const { connectionId } = useParams();
  const [detail, setDetail] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [reveal, setReveal] = useState(false);
  const [databases, setDatabases] = useState([]);
  const [schemas, setSchemas] = useState([]);
  const [tables, setTables] = useState([]);
  const [columns, setColumns] = useState([]);
  const [rowColumns, setRowColumns] = useState([]);
  const [rows, setRows] = useState([]);
  const [selectedDatabase, setSelectedDatabase] = useState("");
  const [selectedSchema, setSelectedSchema] = useState("");
  const [selectedTable, setSelectedTable] = useState("");
  const [loadingDatabases, setLoadingDatabases] = useState(false);
  const [loadingSchemas, setLoadingSchemas] = useState(false);
  const [loadingTables, setLoadingTables] = useState(false);
  const [loadingColumns, setLoadingColumns] = useState(false);
  const [loadingRows, setLoadingRows] = useState(false);
  const [browseError, setBrowseError] = useState("");
  const [tableError, setTableError] = useState("");
  const [rowsError, setRowsError] = useState("");
  const [offset, setOffset] = useState(0);

  const limit = 100;

  const parsed = useMemo(
    () => parseConnectionString(detail?.connection_string),
    [detail]
  );

  useEffect(() => {
    if (!isAuthenticated || !connectionId) return;
    setLoading(true);
    setError("");
    getConnectionString(connectionId, getAccessToken)
      .then((data) => setDetail(data))
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [connectionId, isAuthenticated, getAccessToken]);

  useEffect(() => {
    if (!isAuthenticated || !connectionId) return;
    setLoadingDatabases(true);
    setBrowseError("");
    listConnectionDatabases(connectionId, getAccessToken)
      .then((data) => {
        const list = data?.databases ?? [];
        setDatabases(list);
        setSelectedDatabase((prev) => prev || list[0] || "");
        setSchemas([]);
        setTables([]);
        setColumns([]);
        setRows([]);
        setRowColumns([]);
        setSelectedSchema("");
        setSelectedTable("");
        setOffset(0);
      })
      .catch((err) => setBrowseError(err.message))
      .finally(() => setLoadingDatabases(false));
  }, [connectionId, isAuthenticated, getAccessToken]);

  useEffect(() => {
    if (!isAuthenticated || !selectedDatabase) return;
    setLoadingSchemas(true);
    setBrowseError("");
    listConnectionSchemas(connectionId, selectedDatabase, getAccessToken)
      .then((data) => {
        const list = data?.schemas ?? [];
        setSchemas(list);
        setSelectedSchema((prev) => prev || list[0] || "");
        setTables([]);
        setColumns([]);
        setRows([]);
        setRowColumns([]);
        setSelectedTable("");
        setOffset(0);
      })
      .catch((err) => setBrowseError(err.message))
      .finally(() => setLoadingSchemas(false));
  }, [connectionId, isAuthenticated, selectedDatabase, getAccessToken]);

  useEffect(() => {
    if (!isAuthenticated || !selectedDatabase || !selectedSchema) return;
    setLoadingTables(true);
    setBrowseError("");
    listConnectionTables(
      connectionId,
      selectedDatabase,
      selectedSchema,
      getAccessToken
    )
      .then((data) => {
        const list = data?.tables ?? [];
        setTables(list);
        setSelectedTable((prev) => prev || list[0] || "");
        setColumns([]);
        setRows([]);
        setRowColumns([]);
        setOffset(0);
      })
      .catch((err) => setBrowseError(err.message))
      .finally(() => setLoadingTables(false));
  }, [
    connectionId,
    isAuthenticated,
    selectedDatabase,
    selectedSchema,
    getAccessToken,
  ]);

  useEffect(() => {
    if (
      !isAuthenticated ||
      !selectedDatabase ||
      !selectedSchema ||
      !selectedTable
    )
      return;
    setLoadingColumns(true);
    setTableError("");
    getConnectionTableDetails(
      connectionId,
      selectedDatabase,
      selectedSchema,
      selectedTable,
      getAccessToken
    )
      .then((data) => setColumns(data?.columns ?? []))
      .catch((err) => setTableError(err.message))
      .finally(() => setLoadingColumns(false));
  }, [
    connectionId,
    isAuthenticated,
    selectedDatabase,
    selectedSchema,
    selectedTable,
    getAccessToken,
  ]);

  useEffect(() => {
    if (
      !isAuthenticated ||
      !selectedDatabase ||
      !selectedSchema ||
      !selectedTable
    )
      return;
    setLoadingRows(true);
    setRowsError("");
    getConnectionTableRows(
      connectionId,
      selectedDatabase,
      selectedSchema,
      selectedTable,
      limit,
      offset,
      getAccessToken
    )
      .then((data) => {
        setRowColumns(data?.columns ?? []);
        setRows(data?.rows ?? []);
      })
      .catch((err) => setRowsError(err.message))
      .finally(() => setLoadingRows(false));
  }, [
    connectionId,
    isAuthenticated,
    selectedDatabase,
    selectedSchema,
    selectedTable,
    limit,
    offset,
    getAccessToken,
  ]);

  useEffect(() => {
    setOffset(0);
  }, [selectedTable]);

  if (!isAuthenticated) {
    return (
      <section className="panel">
        <h2>PostgreSQL deep dive</h2>
        <p className="muted">Sign in to inspect a PostgreSQL connection.</p>
      </section>
    );
  }

  const connectionName = detail?.name || "PostgreSQL connection";

  return (
    <>
      <section className="panel">
        <div className="panel-header">
          <div>
            <h2>{connectionName}</h2>
            <p className="muted">
              Database details for the selected PostgreSQL connection.
            </p>
          </div>
          <Link className="btn ghost" to="/connections">
            Back to connections
          </Link>
        </div>

        {loading ? <p className="muted">Loading connection...</p> : null}
        {error ? <p className="notice error">{error}</p> : null}

        {detail ? (
          <>
            <div className="detail-grid">
              <div className="detail-item">
                <span>Name</span>
                <strong>{detail.name}</strong>
              </div>
              <div className="detail-item">
                <span>Created</span>
                <strong>
                  {detail.created_at
                    ? new Date(detail.created_at).toLocaleString()
                    : "-"}
                </strong>
              </div>
              <div className="detail-item">
                <span>Updated</span>
                <strong>
                  {detail.updated_at
                    ? new Date(detail.updated_at).toLocaleString()
                    : "-"}
                </strong>
              </div>
              <div className="detail-item">
                <span>SSL mode</span>
                <strong>{parsed?.sslmode || "-"}</strong>
              </div>
            </div>

            <div className="panel">
              <div className="panel-header">
                <div>
                  <h3>Connection string</h3>
                  <p className="muted">
                    Reveal to view the full credentials for this connection.
                  </p>
                </div>
                <button
                  className="btn"
                  type="button"
                  onClick={() => setReveal((prev) => !prev)}
                >
                  {reveal ? "Hide" : "Reveal"}
                </button>
              </div>
              <p className="detail-mono">
                {reveal ? detail.connection_string : "Hidden"}
              </p>
            </div>

            <div className="panel">
              <div className="panel-header">
                <div>
                  <h3>Database details</h3>
                  <p className="muted">
                    Parsed from the connection string for quick reference.
                  </p>
                </div>
              </div>

              {parsed?.error ? (
                <p className="notice error">{parsed.error}</p>
              ) : (
                <div className="detail-grid">
                  <div className="detail-item">
                    <span>Host</span>
                    <strong>{parsed?.host || "-"}</strong>
                  </div>
                  <div className="detail-item">
                    <span>Port</span>
                    <strong>{parsed?.port || "-"}</strong>
                  </div>
                  <div className="detail-item">
                    <span>Database</span>
                    <strong>{parsed?.database || "-"}</strong>
                  </div>
                  <div className="detail-item">
                    <span>User</span>
                    <strong>{parsed?.user || "-"}</strong>
                  </div>
                  <div className="detail-item">
                    <span>Password</span>
                    <strong>{parsed?.password || "-"}</strong>
                  </div>
                  <div className="detail-item">
                    <span>Parameters</span>
                    <strong>
                      {parsed?.params && Object.keys(parsed.params).length > 0
                        ? Object.keys(parsed.params).join(", ")
                        : "-"}
                    </strong>
                  </div>
                </div>
              )}
            </div>

            <div className="panel">
              <div className="panel-header">
                <div>
                  <h3>Data explorer</h3>
                  <p className="muted">
                    Navigate databases, schemas, and tables for this connection.
                  </p>
                </div>
              </div>

              <div className="form-grid">
                <label className="field">
                  <span>Database</span>
                  <select
                    value={selectedDatabase}
                    onChange={(event) => setSelectedDatabase(event.target.value)}
                    disabled={loadingDatabases}
                  >
                    <option value="">Select database</option>
                    {databases.map((db) => (
                      <option key={db} value={db}>
                        {db}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  <span>Schema</span>
                  <select
                    value={selectedSchema}
                    onChange={(event) => setSelectedSchema(event.target.value)}
                    disabled={!selectedDatabase || loadingSchemas}
                  >
                    <option value="">Select schema</option>
                    {schemas.map((schema) => (
                      <option key={schema} value={schema}>
                        {schema}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  <span>Table</span>
                  <select
                    value={selectedTable}
                    onChange={(event) => setSelectedTable(event.target.value)}
                    disabled={!selectedSchema || loadingTables}
                  >
                    <option value="">Select table</option>
                    {tables.map((table) => (
                      <option key={table} value={table}>
                        {table}
                      </option>
                    ))}
                  </select>
                </label>
              </div>

              {browseError ? <p className="notice error">{browseError}</p> : null}
              {loadingDatabases || loadingSchemas || loadingTables ? (
                <p className="muted">Loading metadata...</p>
              ) : null}
            </div>

            <div className="panel">
              <div className="panel-header">
                <div>
                  <h3>Table details</h3>
                  <p className="muted">
                    Column metadata for the selected table.
                  </p>
                </div>
              </div>

              {tableError ? <p className="notice error">{tableError}</p> : null}
              {loadingColumns ? (
                <p className="muted">Loading column details...</p>
              ) : null}
              {!loadingColumns && columns.length === 0 ? (
                <p className="muted">Select a table to view columns.</p>
              ) : null}

              {columns.length > 0 ? (
                <div className="table-scroll">
                  <table className="data-table">
                    <thead>
                      <tr>
                        <th>Name</th>
                        <th>Type</th>
                        <th>Nullable</th>
                        <th>Default</th>
                        <th>Position</th>
                      </tr>
                    </thead>
                    <tbody>
                      {columns.map((column) => (
                        <tr key={`${column.name}-${column.position}`}>
                          <td>{column.name}</td>
                          <td>{column.type}</td>
                          <td>{column.nullable}</td>
                          <td>{column.default ?? "-"}</td>
                          <td>{column.position}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : null}
            </div>

            <div className="panel">
              <div className="panel-header">
                <div>
                  <h3>Table content</h3>
                  <p className="muted">
                    Showing up to {limit} rows per page.
                  </p>
                </div>
                <div className="pagination">
                  <button
                    className="btn ghost"
                    type="button"
                    onClick={() => setOffset((prev) => Math.max(prev - limit, 0))}
                    disabled={offset === 0 || loadingRows}
                  >
                    Prev
                  </button>
                  <button
                    className="btn ghost"
                    type="button"
                    onClick={() => setOffset((prev) => prev + limit)}
                    disabled={rows.length < limit || loadingRows}
                  >
                    Next
                  </button>
                </div>
              </div>

              {rowsError ? <p className="notice error">{rowsError}</p> : null}
              {loadingRows ? (
                <p className="muted">Loading rows...</p>
              ) : null}
              {!loadingRows && rows.length === 0 ? (
                <p className="muted">Select a table to view rows.</p>
              ) : null}

              {rows.length > 0 ? (
                <div className="table-scroll">
                  <table className="data-table">
                    <thead>
                      <tr>
                        {rowColumns.map((column) => (
                          <th key={column}>{column}</th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((row, index) => (
                        <tr key={`${selectedTable}-${offset}-${index}`}>
                          {rowColumns.map((column) => (
                            <td key={`${column}-${index}`}>
                              {row[column] === null || row[column] === undefined
                                ? "-"
                                : String(row[column])}
                            </td>
                          ))}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : null}
            </div>
          </>
        ) : null}
      </section>
    </>
  );
}

export default PostgreSQLConnectionDetail;
