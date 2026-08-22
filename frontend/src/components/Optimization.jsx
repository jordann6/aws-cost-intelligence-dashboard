import React from 'react'

// Coverage (RI / Savings Plans) plus idle-resource waste, with an estimated
// monthly $ left on the table — the highest-signal FinOps view.
export default function Optimization({ coverage, waste }) {
  const latest = {}
  for (const c of coverage) {
    if (!latest[c.kind] || c.period > latest[c.kind].period) latest[c.kind] = c
  }
  const cov = Object.values(latest)
  const wasteTotal = waste.reduce((sum, w) => sum + Number(w.est_monthly_usd || 0), 0)

  return (
    <div>
      <div style={covRow}>
        {cov.length === 0 && <span style={empty}>No coverage data yet.</span>}
        {cov.map(c => {
          const pct = Number(c.coverage_pct || 0)
          const low = pct < 70
          return (
            <div key={c.kind} style={covCard}>
              <div style={{ fontSize: 11, color: '#555' }}>{c.kind} coverage</div>
              <div style={{ fontSize: 22, fontWeight: 600, color: low ? '#f59e0b' : '#22c55e' }}>{pct.toFixed(0)}%</div>
            </div>
          )
        })}
      </div>

      {waste.length === 0 ? (
        <p style={empty}>No idle resources found.</p>
      ) : (
        <>
          <div style={{ fontSize: 12, color: '#f59e0b', margin: '6px 0 10px' }}>
            ~${wasteTotal.toFixed(2)}/mo wasted across {waste.length} resources
          </div>
          <table style={table}>
            <thead>
              <tr>{['Resource', 'Issue', '$/mo'].map(h => <th key={h} style={th}>{h}</th>)}</tr>
            </thead>
            <tbody>
              {waste.slice(0, 10).map((w, i) => (
                <tr key={i}>
                  <td style={{ ...td, fontFamily: 'monospace', fontSize: 11 }} title={w.detail}>{w.resource}</td>
                  <td style={td}><span style={badge}>{w.issue}</span></td>
                  <td style={{ ...td, fontFamily: 'monospace' }}>${Number(w.est_monthly_usd || 0).toFixed(2)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </div>
  )
}

const covRow = { display: 'flex', gap: 12, marginBottom: 14 }
const covCard = { background: '#101010', border: '1px solid #1c1c1c', borderRadius: 5, padding: '10px 14px', minWidth: 110 }
const table = { width: '100%', borderCollapse: 'collapse', fontSize: '12px' }
const th = { textAlign: 'left', padding: '5px 8px', color: '#444', fontWeight: 500, borderBottom: '1px solid #1c1c1c' }
const td = { padding: '5px 8px', borderBottom: '1px solid #181818', color: '#bbb' }
const badge = { background: '#1e1a10', color: '#f59e0b', padding: '1px 6px', borderRadius: '3px', fontSize: '11px' }
const empty = { color: '#444', fontSize: '13px' }
