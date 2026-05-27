import os
import statistics
import boto3
from decimal import Decimal
from datetime import date, timedelta
from boto3.dynamodb.conditions import Key

Z_THRESHOLD = 2.5
FORECAST_DAYS = 14


def z_score(values):
    if len(values) < 3:
        return 0.0
    mean = statistics.mean(values)
    stdev = statistics.pstdev(values) or 1.0
    return round((values[-1] - mean) / stdev, 2)


def linear_forecast(totals, days=FORECAST_DAYS):
    n = len(totals)
    if n < 7:
        return []
    x_mean = (n - 1) / 2
    y_mean = statistics.mean(totals)
    num = sum((i - x_mean) * (v - y_mean) for i, v in enumerate(totals))
    den = sum((i - x_mean) ** 2 for i in range(n)) or 1.0
    slope = num / den
    intercept = y_mean - slope * x_mean
    return [max(0.0, slope * (n + i) + intercept) for i in range(days)]


def handler(event, context):
    table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
    sns = boto3.client("sns")
    alert_topic = os.environ.get("ALERT_TOPIC_ARN", "")

    today = date.today().strftime("%Y-%m-%d")
    start = (date.today() - timedelta(days=30)).strftime("%Y-%m-%d")

    # Fetch all DAILY records for the last 30 days in one query
    resp = table.query(
        KeyConditionExpression=Key("pk").eq("DAILY") & Key("sk").between(f"{start}#", f"{today}#~")
    )

    # Build service → {date: cost} map
    service_history: dict[str, dict[str, float]] = {}
    for item in resp.get("Items", []):
        svc = item["service"]
        if svc not in service_history:
            service_history[svc] = {}
        service_history[svc][item["date"]] = float(item["cost"])

    anomalies = []

    with table.batch_writer() as batch:
        for svc, day_costs in service_history.items():
            sorted_costs = [day_costs[d] for d in sorted(day_costs)]
            z = z_score(sorted_costs)
            if abs(z) > Z_THRESHOLD:
                anomalies.append({"service": svc, "z_score": z, "cost": sorted_costs[-1]})
                batch.put_item(Item={
                    "pk": "ANOMALY",
                    "sk": f"{today}#{svc}",
                    "date": today,
                    "service": svc,
                    "z_score": Decimal(str(z)),
                    "cost": Decimal(str(sorted_costs[-1])),
                    "baseline_mean": Decimal(str(round(statistics.mean(sorted_costs[:-1]), 4))),
                })

    # Compute daily totals across all services and generate forecast
    date_totals: dict[str, float] = {}
    for day_costs in service_history.values():
        for d, c in day_costs.items():
            date_totals[d] = date_totals.get(d, 0.0) + c

    sorted_totals = [date_totals.get(d, 0.0) for d in sorted(date_totals)]
    forecast = linear_forecast(sorted_totals)

    with table.batch_writer() as batch:
        for i, f_cost in enumerate(forecast):
            f_date = (date.today() + timedelta(days=i + 1)).strftime("%Y-%m-%d")
            batch.put_item(Item={
                "pk": "FORECAST",
                "sk": f_date,
                "forecast_date": f_date,
                "forecast_cost": Decimal(str(round(f_cost, 4))),
            })

    if anomalies and alert_topic:
        lines = "\n".join(
            f"  {a['service']}: ${a['cost']:.2f} (z={a['z_score']})" for a in anomalies
        )
        sns.publish(
            TopicArn=alert_topic,
            Subject=f"[Cost Alert] {len(anomalies)} anomaly detected — {today}",
            Message=f"Cost anomalies detected on {today}:\n\n{lines}\n\nZ-score threshold: {Z_THRESHOLD}",
        )

    return {
        "statusCode": 200,
        "anomalies": len(anomalies),
        "forecast_days": len(forecast),
    }
