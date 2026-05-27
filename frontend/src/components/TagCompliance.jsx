import React from 'react'

export default function TagCompliance({ data }) {
  if (!data.length) return <p style={empty}>All resources are compliant.</p>

  return (
    <table style={table}>
      <thead>
        <tr>{['Resource', 'Missing Tags'].map(h => <th key={h} style={th}>{h}</th>)}</tr>
      </thead>
      <tbody>
        {data.slice(0, 10).map((r, i) => {
          const name = r.arn.split('/').pop() || r.arn.split(':').pop() || r.arn
          return (
            <tr key={i}>
              <td style={{ ...td, fontFamily: 'monospace', fontSize: '11px', maxWidth: 160, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={r.arn}>
                {name}
              </td>
              <td style={td}>
                {r.missing_tags.map(t => <span key={t} style={badge}>{t}</span>)}
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
const badge = { background: '#1e1a10', color: '#f59e0b', padding: '1px 6px', borderRadius: '3px', fontSize: '11px', marginRight: '4px', display: 'inline-block' }
const empty = { color: '#444', fontSize: '13px' }
