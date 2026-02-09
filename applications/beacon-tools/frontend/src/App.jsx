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

function App() {
  return (
    <div className="app">
      <header className="hero">
        <div>
          <p className="eyebrow">Beacon Platform</p>
          <h1>Tools</h1>
          <p className="subtitle">
            Your control panel for Beacon utilities and automations.
          </p>
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
          <p className="muted">Add serverless services next.</p>
        </div>
      </header>

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
        <h2>Next steps</h2>
        <ul className="list">
          <li>Spin up the first serverless Python service.</li>
          <li>Connect API routes behind NGINX.</li>
          <li>Add authentication and role-based access.</li>
        </ul>
      </section>
    </div>
  );
}

export default App;
