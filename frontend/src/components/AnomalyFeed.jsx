import React from 'react'

export default function AnomalyFeed({ data }) {
  const rows = [...data].sort((a, b) => b.date.localeCompare(a.date)).slice(0, 10)
  if (!rows.length) return <p style={empty}>No anomalies detected.</p>

  return (
    <table style={table}>
      <thead>
        <tr>{['Date', 'Service', 'Cost', 'Z-Score'].map(h => <th key={h} style={th}>{h}</th>)}</tr>
      </thead>
      <tbody>
        {rows.map((a, i) => {
          const z = parseFloat(a.z_score)
          return (
            <tr key={i}>
              <td style={td}>{a.date}</td>
              <td style={{ ...td, maxWidth: 160, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={a.service}>{a.service}</td>
              <td style={td}>${parseFloat(a.cost).toFixed(2)}</td>
              <td style={{ ...td, color: Math.abs(z) > 3 ? '#ef4444' : '#f59e0b', fontWeight: 500 }}>{z.toFixed(2)}</td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}

const table = { width: '100%', borderCollapse: 'collapse', fontSize: '12px' }
const th = { textAlign: 'left', padding: '5px 8px', color: '#444', fontWeight: 500, borderBottom: '1px solid #1c1c1c' }
const td = { padding: '5px 8px', borderBottom: '1px solid #181818', color: '#bbb' }
const empty = { color: '#444', fontSize: '13px' }
