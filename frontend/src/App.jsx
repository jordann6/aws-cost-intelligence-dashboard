import React, { useEffect, useState } from 'react'
import CostChart from './components/CostChart'
import ForecastChart from './components/ForecastChart'
import AnomalyFeed from './components/AnomalyFeed'
import TagCompliance from './components/TagCompliance'
import CostByTag from './components/CostByTag'
import Optimization from './components/Optimization'

const API = import.meta.env.VITE_API_URL || ''

const s = {
  root: { fontFamily: 'system-ui, -apple-system, sans-serif', background: '#0c0c0c', minHeight: '100vh', color: '#e2e2e2' },
  loading: { display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100vh', color: '#444', fontFamily: 'system-ui, sans-serif', fontSize: '13px' },
  header: { padding: '20px 28px', borderBottom: '1px solid #1c1c1c', display: 'flex', alignItems: 'baseline', gap: '16px' },
  title: { margin: 0, fontSize: '16px', fontWeight: 600, letterSpacing: '-0.02em' },
  sub: { fontSize: '11px', color: '#444' },
  main: { padding: '20px 28px', display: 'flex', flexDirection: 'column', gap: '16px' },
  card: { background: '#141414', border: '1px solid #1c1c1c', borderRadius: '6px', padding: '18px 20px' },
  label: { margin: '0 0 14px', fontSize: '11px', fontWeight: 500, color: '#555', textTransform: 'uppercase', letterSpacing: '0.1em' },
  row: { display: 'flex', gap: '16px' },
}

export default function App() {
  const [data, setData] = useState(null)

  useEffect(() => {
    Promise.all([
      fetch(`${API}/costs`).then(r => r.json()).catch(() => []),
      fetch(`${API}/forecast`).then(r => r.json()).catch(() => []),
      fetch(`${API}/anomalies`).then(r => r.json()).catch(() => []),
      fetch(`${API}/tags`).then(r => r.json()).catch(() => []),
      fetch(`${API}/costs-by-tag`).then(r => r.json()).catch(() => []),
      fetch(`${API}/coverage`).then(r => r.json()).catch(() => []),
      fetch(`${API}/waste`).then(r => r.json()).catch(() => []),
    ]).then(([costs, forecast, anomalies, tags, costsByTag, coverage, waste]) =>
      setData({ costs, forecast, anomalies, tags, costsByTag, coverage, waste }))
  }, [])

  if (!data) return <div style={s.loading}>Loading...</div>

  return (
    <div style={s.root}>
      <header style={s.header}>
        <h1 style={s.title}>Cost Intelligence Dashboard</h1>
        <span style={s.sub}>AWS · us-east-1 · Updated daily 01:00 / 02:00 UTC</span>
      </header>
      <main style={s.main}>
        <section style={s.card}>
          <p style={s.label}>30-Day Cost Trend</p>
          <CostChart data={data.costs} />
        </section>
        <section style={s.card}>
          <p style={s.label}>14-Day Forecast</p>
          <ForecastChart data={data.forecast} />
        </section>
        <div style={s.row}>
          <section style={{ ...s.card, flex: 1, minWidth: 0 }}>
            <p style={s.label}>Spend by Owner (30d · tag: Project)</p>
            <CostByTag data={data.costsByTag} />
          </section>
          <section style={{ ...s.card, flex: 1, minWidth: 0 }}>
            <p style={s.label}>Optimization · Coverage &amp; Waste</p>
            <Optimization coverage={data.coverage} waste={data.waste} />
          </section>
        </div>
        <div style={s.row}>
          <section style={{ ...s.card, flex: 1, minWidth: 0 }}>
            <p style={s.label}>Anomalies</p>
            <AnomalyFeed data={data.anomalies} />
          </section>
          <section style={{ ...s.card, flex: 1, minWidth: 0 }}>
            <p style={s.label}>Tag Compliance Issues</p>
            <TagCompliance data={data.tags} />
          </section>
        </div>
      </main>
    </div>
  )
}
