import { useMemo, useState } from "react";

const defaultBackendUrl = "/toolsuite-api";

export default function App() {
  const [message, setMessage] = useState("ping");
  const [result, setResult] = useState(null);
  const [error, setError] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  const backendUrl = useMemo(() => {
    return import.meta.env.VITE_BACKEND_URL || defaultBackendUrl;
  }, []);

  const handleSubmit = async (event) => {
    event.preventDefault();
    setError("");
    setResult(null);
    setIsLoading(true);

    try {
      const response = await fetch(`${backendUrl}/tools/ping`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message }),
      });

      if (!response.ok) {
        throw new Error(`Request failed with ${response.status}`);
      }

      const payload = await response.json();
      setResult(payload);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Request failed");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <main className="page">
      <section className="card">
        <header>
          <h1>Toolsuite</h1>
          <p className="subtitle">
            Run small tools backed by the Toolsuite API.
          </p>
        </header>

        <form className="form" onSubmit={handleSubmit}>
          <label className="field">
            <span>Message</span>
            <input
              type="text"
              value={message}
              onChange={(event) => setMessage(event.target.value)}
            />
          </label>
          <button type="submit" disabled={isLoading}>
            {isLoading ? "Running..." : "Run ping"}
          </button>
        </form>

        {error && <p className="error">Tool failed: {error}</p>}
        {result && (
          <div className="result">
            <h2>Result</h2>
            <pre>{JSON.stringify(result, null, 2)}</pre>
          </div>
        )}
      </section>
    </main>
  );
}
