import json
import os
import boto3
from datetime import date, timedelta
from decimal import Decimal

REQUIRED_TAGS = json.loads(os.environ.get("REQUIRED_TAGS", '["Environment", "Project", "ManagedBy"]'))


def handler(event, context):
    ce = boto3.client("ce", region_name="us-east-1")
    tagging = boto3.client("resourcegroupstaggingapi")
    table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])

    end = date.today().strftime("%Y-%m-%d")
    start = (date.today() - timedelta(days=90)).strftime("%Y-%m-%d")

    # Pull 90 days of daily cost data grouped by service
    response = ce.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="DAILY",
        Metrics=["UnblendedCost"],
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
    )

    with table.batch_writer() as batch:
        for result in response["ResultsByTime"]:
            day = result["TimePeriod"]["Start"]
            for group in result["Groups"]:
                service = group["Keys"][0]
                cost = Decimal(str(group["Metrics"]["UnblendedCost"]["Amount"]))
                if cost > 0:
                    batch.put_item(Item={
                        "pk": "DAILY",
                        "sk": f"{day}#{service}",
                        "date": day,
                        "service": service,
                        "cost": cost,
                    })

    # Scan for tag compliance — flag resources missing required tags
    paginator = tagging.get_paginator("get_resources")
    with table.batch_writer() as batch:
        # Clear stale tag issues before re-scanning
        existing = table.query(KeyConditionExpression=boto3.dynamodb.conditions.Key("pk").eq("TAG_ISSUE"))
        for item in existing.get("Items", []):
            batch.delete_item(Key={"pk": "TAG_ISSUE", "sk": item["sk"]})

        for page in paginator.paginate(ResourcesPerPage=100):
            for resource in page["ResourceTagMappingList"]:
                arn = resource["ResourceARN"]
                existing_keys = {t["Key"] for t in resource.get("Tags", [])}
                missing = [t for t in REQUIRED_TAGS if t not in existing_keys]
                if missing:
                    batch.put_item(Item={
                        "pk": "TAG_ISSUE",
                        "sk": arn,
                        "arn": arn,
                        "missing_tags": missing,
                    })

    return {"statusCode": 200, "message": "Ingestion complete", "period": f"{start} → {end}"}
