import React, { useEffect, useMemo, useState } from "react";
import {
  addTestCase,
  createRun,
  createTestSuite,
  getRun,
  getRuns,
  getTestSuites,
} from "./services/api.js";

const emptySuiteForm = { name: "", description: "" };

function App() {
  const [suites, setSuites] = useState([]);
  const [runs, setRuns] = useState([]);
  const [suiteForm, setSuiteForm] = useState(emptySuiteForm);
  const [caseForms, setCaseForms] = useState({});
  const [selectedRunId, setSelectedRunId] = useState(null);
  const [selectedRun, setSelectedRun] = useState(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const sortedRuns = useMemo(() => runs, [runs]);

  const loadSuites = async () => {
    const data = await getTestSuites();
    setSuites(data);
  };

  const loadRuns = async () => {
    const data = await getRuns();
    setRuns(data);
  };

  const refreshAll = async () => {
    setError("");
    try {
      await Promise.all([loadSuites(), loadRuns()]);
    } catch (err) {
      setError(err.message);
    }
  };

  useEffect(() => {
    refreshAll();
  }, []);

  useEffect(() => {
    if (!selectedRunId) {
      setSelectedRun(null);
      return;
    }
    getRun(selectedRunId)
      .then(setSelectedRun)
      .catch((err) => setError(err.message));
  }, [selectedRunId]);

  const handleCreateSuite = async (event) => {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      await createTestSuite({ ...suiteForm, cases: [] });
      setSuiteForm(emptySuiteForm);
      await loadSuites();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const handleAddCase = async (suiteId) => {
    const form = caseForms[suiteId];
    if (!form) {
      return;
    }
    setBusy(true);
    setError("");
    try {
      let rubric = null;
      if (form.rubric) {
        rubric = JSON.parse(form.rubric);
      }
      await addTestCase(suiteId, {
        name: form.name,
        prompt: form.prompt,
        expected_response: form.expected_response,
        rubric,
      });
      setCaseForms((prev) => ({ ...prev, [suiteId]: emptyCaseForm() }));
      await loadSuites();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const handleRunSuite = async (suiteId) => {
    setBusy(true);
    setError("");
    try {
      const run = await createRun(suiteId);
      await loadRuns();
      setSelectedRunId(run.id);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const updateCaseForm = (suiteId, field, value) => {
    setCaseForms((prev) => ({
      ...prev,
      [suiteId]: { ...(prev[suiteId] || emptyCaseForm()), [field]: value },
    }));
  };

  return (
    <div className="app">
      <header className="header">
        <h1>Beacon QA</h1>
        <p>Phase 1: prompt/response + rubric scoring</p>
      </header>

      {error && <div className="error">{error}</div>}

      <section className="panel">
        <h2>Create test suite</h2>
        <form onSubmit={handleCreateSuite} className="form">
          <input
            type="text"
            placeholder="Suite name"
            value={suiteForm.name}
            onChange={(event) => setSuiteForm({ ...suiteForm, name: event.target.value })}
            required
          />
          <textarea
            placeholder="Description"
            value={suiteForm.description}
            onChange={(event) => setSuiteForm({ ...suiteForm, description: event.target.value })}
            rows={2}
          />
          <button type="submit" disabled={busy}>
            Create suite
          </button>
        </form>
      </section>

      <section className="panel">
        <h2>Test suites</h2>
        <div className="grid">
          {suites.map((suite) => {
            const hasCases = (suite.cases || []).length > 0;
            return (
            <div key={suite.id} className="card">
              <div className="card-header">
                <div>
                  <h3>{suite.name}</h3>
                  <p>{suite.description || "No description"}</p>
                  {!hasCases && <p className="muted">Add at least one test case to run.</p>}
                </div>
                <button
                  onClick={() => handleRunSuite(suite.id)}
                  disabled={busy}
                  title="Run suite"
                >
                  Run suite
                </button>
              </div>
              <div className="cases">
                {(suite.cases || []).map((testCase) => (
                  <div key={testCase.id} className="case">
                    <strong>{testCase.name}</strong>
                    <p>{testCase.prompt}</p>
                  </div>
                ))}
              </div>
              <div className="form">
                <input
                  type="text"
                  placeholder="Case name"
                  value={(caseForms[suite.id] || emptyCaseForm()).name}
                  onChange={(event) => updateCaseForm(suite.id, "name", event.target.value)}
                />
                <textarea
                  placeholder="Prompt"
                  rows={3}
                  value={(caseForms[suite.id] || emptyCaseForm()).prompt}
                  onChange={(event) => updateCaseForm(suite.id, "prompt", event.target.value)}
                />
                <textarea
                  placeholder="Expected response"
                  rows={2}
                  value={(caseForms[suite.id] || emptyCaseForm()).expected_response}
                  onChange={(event) => updateCaseForm(suite.id, "expected_response", event.target.value)}
                />
                <textarea
                  placeholder="Rubric JSON (optional)"
                  rows={2}
                  value={(caseForms[suite.id] || emptyCaseForm()).rubric}
                  onChange={(event) => updateCaseForm(suite.id, "rubric", event.target.value)}
                />
                <button onClick={() => handleAddCase(suite.id)} disabled={busy}>
                  Add case
                </button>
              </div>
            </div>
            );
          })}
        </div>
      </section>

      <section className="panel">
        <h2>Runs</h2>
        <div className="runs">
          {sortedRuns.map((run) => (
            <button
              key={run.id}
              className={`run-item ${run.id === selectedRunId ? "active" : ""}`}
              onClick={() => setSelectedRunId(run.id)}
            >
              <div>{run.id.slice(0, 8)}</div>
              <div className="muted">{run.status}</div>
            </button>
          ))}
        </div>
        {selectedRun && (
          <div className="run-detail">
            <h3>Run details</h3>
            <p>Status: {selectedRun.status}</p>
            <div className="results">
              {selectedRun.results?.map((result) => (
                <div key={result.id} className="result">
                  <div className="result-header">
                    <span>Case {result.case_id.slice(0, 8)}</span>
                    <span className="muted">{result.status}</span>
                  </div>
                  {result.agent_response && <pre>{result.agent_response}</pre>}
                  {result.score !== null && (
                    <div className="score">Score: {result.score}</div>
                  )}
                  {result.error && <div className="error">{result.error}</div>}
                </div>
              ))}
            </div>
          </div>
        )}
      </section>
    </div>
  );
}

function emptyCaseForm() {
  return { name: "", prompt: "", expected_response: "", rubric: "" };
}

export default App;
