import React from 'react'

// Aggregates the last 30 days of tag-grouped spend into a per-owner total.
export default function CostByTag({ data }) {
  if (!data.length) return <p style={empty}>No tag-grouped spend yet.</p>

  const totals = {}
  for (const r of data) {
    const key = r.tag_value || `No tag`
    totals[key] = (totals[key] || 0) + Number(r.cost || 0)
  }
  const rows = Object.entries(totals).sort((a, b) => b[1] - a[1])
  const max = rows[0][1] || 1

  return (
    <table style={table}>
      <thead>
        <tr>{['Owner', '30-Day Spend', ''].map(h => <th key={h} style={th}>{h}</th>)}</tr>
      </thead>
      <tbody>
        {rows.map(([name, total]) => {
          const untagged = name.startsWith('No ')
          return (
            <tr key={name}>
              <td style={{ ...td, color: untagged ? '#f59e0b' : '#bbb' }}>{name}</td>
              <td style={{ ...td, fontFamily: 'monospace' }}>${total.toFixed(2)}</td>
              <td style={{ ...td, width: '40%' }}>
                <div style={{ background: untagged ? '#f59e0b' : '#3b82f6', height: 6, borderRadius: 3, width: `${(total / max) * 100}%` }} />
              </td>
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
