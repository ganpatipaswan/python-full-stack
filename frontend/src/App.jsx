import { useEffect, useState } from "react";

function App() {
  const [health, setHealth] = useState(null);
  const [message, setMessage] = useState(null);
  const [items, setItems] = useState([]);
  const [error, setError] = useState("");

  useEffect(() => {
    async function loadData() {
      try {
        const [healthRes, messageRes, itemsRes] = await Promise.all([
          fetch("/api/health"),
          fetch("/api/message"),
          fetch("/api/items"),
        ]);

        if (!healthRes.ok || !messageRes.ok || !itemsRes.ok) {
          throw new Error("Backend API request failed");
        }

        setHealth(await healthRes.json());
        setMessage(await messageRes.json());
        setItems(await itemsRes.json());
      } catch {
        setError(
          "API is not reachable. Start FastAPI with: uvicorn app.main:app --reload --port 8000"
        );
      }
    }

    loadData();
  }, []);

  return (
    <main className="page">
      <section className="hero">
        <p className="eyebrow">FULL-STACK DEMO</p>
        <h1>React.js + FastAPI</h1>
        <p className="subtitle">
          A clean database-free project designed for API integration and
          GitHub Actions CI/CD practice.
        </p>
      </section>

      {error && <div className="error">{error}</div>}

      <section className="grid">
        <article className="card">
          <h2>API Health..</h2>
          <div className={`status ${health?.status === "ok" ? "ok" : ""}`}>
            {health?.status === "ok" ? "● Connected" : "● Checking..."}
          </div>
          <p>{health?.message || "Waiting for backend..."}</p>
        </article>

        <article className="card">
          <h2>Backend Message</h2>
          <p>{message?.message || "Waiting for API..."}</p>
          <small>Database: {message?.database || "—"}</small>
        </article>
      </section>

      <section className="card">
        <h2>Demo Items update</h2>
        <div className="items">
          {items.map((item) => (
            <div className="item" key={item.id}>
              <strong>{item.name}</strong>
              <span>{item.type}</span>
            </div>
          ))}
        </div>
      </section>
    </main>
  );
}

export default App;
