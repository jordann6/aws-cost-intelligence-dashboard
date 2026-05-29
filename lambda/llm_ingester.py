import os
import boto3
from datetime import date, timedelta
from decimal import Decimal
from boto3.dynamodb.conditions import Attr

CENTS_PER_DOLLAR = Decimal("100")


def handler(event, context):
    region = os.environ.get("AWS_REGION_VAR", "us-east-1")
    dynamodb = boto3.resource("dynamodb", region_name=region)

    dashboard_table = dynamodb.Table(os.environ["TABLE_NAME"])
    gateway_table = dynamodb.Table(os.environ["LLM_GATEWAY_TABLE_NAME"])

    yesterday = (date.today() - timedelta(days=1)).strftime("%Y-%m-%d")
    today = date.today().strftime("%Y-%m-%d")

    # Scan gateway request log for all records timestamped yesterday.
    # ISO timestamps are lexicographically sortable, so gte/lt on the date prefix works.
    items = []
    scan_kwargs = {
        "FilterExpression": Attr("timestamp").gte(f"{yesterday}T00:00:00")
        & Attr("timestamp").lt(f"{today}T00:00:00"),
        "ProjectionExpression": "#p, estimated_cost_cents",
        "ExpressionAttributeNames": {"#p": "provider"},
    }

    while True:
        response = gateway_table.scan(**scan_kwargs)
        items.extend(response.get("Items", []))
        if "LastEvaluatedKey" not in response:
            break
        scan_kwargs["ExclusiveStartKey"] = response["LastEvaluatedKey"]

    if not items:
        return {"statusCode": 200, "message": "No LLM requests found", "date": yesterday}

    # Aggregate cost in cents by provider, then convert to dollars before writing.
    provider_totals: dict[str, Decimal] = {}
    for item in items:
        provider = item.get("provider", "unknown")
        cost_cents = Decimal(str(item.get("estimated_cost_cents", 0)))
        provider_totals[provider] = provider_totals.get(provider, Decimal("0")) + cost_cents

    with dashboard_table.batch_writer() as batch:
        for provider, total_cents in provider_totals.items():
            service_name = f"LLM/{provider.capitalize()}"
            cost_dollars = (total_cents / CENTS_PER_DOLLAR).quantize(Decimal("0.0001"))
            batch.put_item(Item={
                "pk": "DAILY",
                "sk": f"{yesterday}#{service_name}",
                "date": yesterday,
                "service": service_name,
                "cost": cost_dollars,
            })

    return {
        "statusCode": 200,
        "message": "LLM cost ingestion complete",
        "date": yesterday,
        "providers": {p: float(t / CENTS_PER_DOLLAR) for p, t in provider_totals.items()},
    }
