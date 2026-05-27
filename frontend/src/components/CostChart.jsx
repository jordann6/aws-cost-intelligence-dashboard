import React, { useMemo } from 'react'
import { LineChart, Line, XAxis, YAxis, Tooltip, Legend, ResponsiveContainer } from 'recharts'

const COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6']

export default function CostChart({ data }) {
  const { chartData, services } = useMemo(() => {
    const byDate = {}
    const svcTotals = {}

    for (const item of data) {
      if (!byDate[item.date]) byDate[item.date] = {}
      const cost = parseFloat(item.cost) || 0
      byDate[item.date][item.service] = cost
      svcTotals[item.service] = (svcTotals[item.service] || 0) + cost
    }

    const top5 = Object.entries(svcTotals)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([s]) => s)

    const chartData = Object.entries(byDate)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([date, svcs]) => ({
        date: date.slice(5),
        ...Object.fromEntries(top5.map(s => [s, parseFloat((svcs[s] || 0).toFixed(2))])),
      }))

    return { chartData, services: top5 }
  }, [data])

  if (!chartData.length) return <Empty />

  return (
    <ResponsiveContainer width="100%" height={260}>
      <LineChart data={chartData} margin={{ top: 4, right: 8, bottom: 0, left: 0 }}>
        <XAxis dataKey="date" tick={tick} interval="preserveStartEnd" />
        <YAxis tick={tick} tickFormatter={v => `$${v}`} width={52} />
        <Tooltip formatter={v => `$${parseFloat(v).toFixed(2)}`} contentStyle={ttStyle} />
        <Legend wrapperStyle={{ fontSize: '11px', paddingTop: '8px' }} />
        {services.map((s, i) => (
          <Line key={s} type="monotone" dataKey={s} stroke={COLORS[i]} dot={false} strokeWidth={1.5} />
        ))}
      </LineChart>
    </ResponsiveContainer>
  )
}

const tick = { fill: '#444', fontSize: 11 }
const ttStyle = { background: '#1a1a1a', border: '1px solid #2a2a2a', fontSize: '12px' }
const Empty = () => <p style={{ color: '#444', fontSize: '13px' }}>No cost data available.</p>
