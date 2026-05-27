import React, { useMemo } from 'react'
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts'

export default function ForecastChart({ data }) {
  const chartData = useMemo(() =>
    [...data]
      .sort((a, b) => a.forecast_date.localeCompare(b.forecast_date))
      .map(d => ({
        date: d.forecast_date.slice(5),
        cost: parseFloat(parseFloat(d.forecast_cost).toFixed(2)),
      })),
    [data]
  )

  if (!chartData.length) return <p style={{ color: '#444', fontSize: '13px' }}>No forecast available — run the analyzer.</p>

  const avg = chartData.reduce((s, d) => s + d.cost, 0) / chartData.length

  return (
    <ResponsiveContainer width="100%" height={180}>
      <AreaChart data={chartData} margin={{ top: 4, right: 8, bottom: 0, left: 0 }}>
        <XAxis dataKey="date" tick={{ fill: '#444', fontSize: 11 }} interval="preserveStartEnd" />
        <YAxis tick={{ fill: '#444', fontSize: 11 }} tickFormatter={v => `$${v}`} width={52} />
        <Tooltip formatter={v => `$${parseFloat(v).toFixed(2)}`} contentStyle={{ background: '#1a1a1a', border: '1px solid #2a2a2a', fontSize: '12px' }} />
        <ReferenceLine y={avg} stroke="#333" strokeDasharray="3 3" label={{ value: 'avg', fill: '#444', fontSize: 10 }} />
        <Area type="monotone" dataKey="cost" stroke="#3b82f6" fill="#3b82f615" strokeWidth={1.5} />
      </AreaChart>
    </ResponsiveContainer>
  )
}
