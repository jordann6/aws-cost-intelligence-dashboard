import json
import os
import boto3
from datetime import date, timedelta
from decimal import Decimal
from boto3.dynamodb.conditions import Key

REQUIRED_TAGS = json.loads(os.environ.get("REQUIRED_TAGS", '["Environment", "Project", "ManagedBy", "CostCenter"]'))
# Which tag key to break spend down by (the "who to bill" dimension).
COST_TAG_KEY = os.environ.get("COST_TAG_KEY", "Project")


def _clear_partition(table, pk):
    """Delete all items under a partition so re-scans start clean."""
    with table.batch_writer() as batch:
        resp = table.query(KeyConditionExpression=Key("pk").eq(pk))
        for item in resp.get("Items", []):
            batch.delete_item(Key={"pk": pk, "sk": item["sk"]})


def ingest_service_costs(ce, table, start, end):
    """90 days of daily spend grouped by SERVICE."""
    resp = ce.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="DAILY",
        Metrics=["UnblendedCost"],
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
    )
    with table.batch_writer() as batch:
        for result in resp["ResultsByTime"]:
            day = result["TimePeriod"]["Start"]
            for group in result["Groups"]:
                service = group["Keys"][0]
                cost = Decimal(str(group["Metrics"]["UnblendedCost"]["Amount"]))
                if cost > 0:
                    batch.put_item(Item={
                        "pk": "DAILY",
                        "sk": f"{day}#{service}",
                        "date": day, "service": service, "cost": cost,
                    })


def ingest_tag_costs(ce, table, start, end):
    """90 days of daily spend grouped by a cost allocation tag (who to bill).

    Requires the tag key to be activated as a cost allocation tag; until then
    Cost Explorer returns everything under the empty-value bucket. Untagged
    spend surfaces as the literal 'No <TagKey>' key, which is itself a signal.
    """
    _clear_partition(table, "DAILY_TAG")
    resp = ce.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="DAILY",
        Metrics=["UnblendedCost"],
        GroupBy=[{"Type": "TAG", "Key": COST_TAG_KEY}],
    )
    with table.batch_writer() as batch:
        for result in resp["ResultsByTime"]:
            day = result["TimePeriod"]["Start"]
            for group in result["Groups"]:
                raw = group["Keys"][0]  # e.g. "Project$cost-dashboard"
                value = raw.split("$", 1)[-1] or f"No {COST_TAG_KEY}"
                cost = Decimal(str(group["Metrics"]["UnblendedCost"]["Amount"]))
                if cost > 0:
                    batch.put_item(Item={
                        "pk": "DAILY_TAG",
                        "sk": f"{day}#{value}",
                        "date": day, "tag_key": COST_TAG_KEY,
                        "tag_value": value, "cost": cost,
                    })


def ingest_coverage(ce, table, start, end):
    """RI + Savings Plans coverage. Low coverage on steady-state spend = money
    left on the table vs. on-demand pricing."""
    _clear_partition(table, "COVERAGE")
    items = []

    ri = ce.get_reservation_coverage(
        TimePeriod={"Start": start, "End": end},
        Granularity="MONTHLY",
    )
    for period in ri.get("CoveragesByTime", []):
        pct = period["Total"]["CoverageHours"]["CoverageHoursPercentage"]
        items.append({"kind": "RI", "coverage_pct": Decimal(str(pct)),
                      "period": period["TimePeriod"]["Start"]})

    sp = ce.get_savings_plans_coverage(
        TimePeriod={"Start": start, "End": end},
        Granularity="MONTHLY",
    )
    for period in sp.get("SavingsPlansCoverages", []):
        pct = period["Coverage"]["CoveragePercentage"]
        items.append({"kind": "SavingsPlans", "coverage_pct": Decimal(str(pct)),
                      "period": period["TimePeriod"]["Start"]})

    with table.batch_writer() as batch:
        for it in items:
            batch.put_item(Item={
                "pk": "COVERAGE", "sk": f"{it['kind']}#{it['period']}", **it,
            })


def scan_waste(ec2, table):
    """Surface idle resources that cost money for nothing: unattached EBS
    volumes, unassociated Elastic IPs, and legacy gp2 volumes (gp3 is ~20%
    cheaper for the same performance)."""
    _clear_partition(table, "WASTE")
    findings = []

    vols = ec2.get_paginator("describe_volumes")
    for page in vols.paginate():
        for v in page["Volumes"]:
            vid = v["VolumeId"]
            size = v["Size"]
            if v["State"] == "available":  # not attached to anything
                findings.append({
                    "resource": vid, "type": "EBS",
                    "issue": "unattached", "detail": f"{size} GiB idle",
                    "est_monthly_usd": Decimal(str(round(size * 0.08, 2))),
                })
            elif v["VolumeType"] == "gp2":
                findings.append({
                    "resource": vid, "type": "EBS",
                    "issue": "gp2-not-gp3", "detail": f"{size} GiB on gp2",
                    "est_monthly_usd": Decimal(str(round(size * 0.02, 2))),
                })

    addrs = ec2.describe_addresses()
    for a in addrs.get("Addresses", []):
        if "AssociationId" not in a:  # allocated but not attached = billed
            findings.append({
                "resource": a.get("AllocationId", a.get("PublicIp", "eip")),
                "type": "EIP", "issue": "unassociated",
                "detail": a.get("PublicIp", ""),
                "est_monthly_usd": Decimal("3.60"),
            })

    with table.batch_writer() as batch:
        for f in findings:
            batch.put_item(Item={
                "pk": "WASTE", "sk": f"{f['type']}#{f['resource']}", **f,
            })


def scan_tag_compliance(tagging, table):
    """Flag resources missing any required tag key (exact-match, TitleCase)."""
    _clear_partition(table, "TAG_ISSUE")
    paginator = tagging.get_paginator("get_resources")
    with table.batch_writer() as batch:
        for page in paginator.paginate(ResourcesPerPage=100):
            for resource in page["ResourceTagMappingList"]:
                arn = resource["ResourceARN"]
                existing_keys = {t["Key"] for t in resource.get("Tags", [])}
                missing = [t for t in REQUIRED_TAGS if t not in existing_keys]
                if missing:
                    batch.put_item(Item={
                        "pk": "TAG_ISSUE", "sk": arn,
                        "arn": arn, "missing_tags": missing,
                    })


def handler(event, context):
    ce = boto3.client("ce", region_name="us-east-1")
    tagging = boto3.client("resourcegroupstaggingapi")
    ec2 = boto3.client("ec2")
    table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])

    end = date.today().strftime("%Y-%m-%d")
    start = (date.today() - timedelta(days=90)).strftime("%Y-%m-%d")

    ingest_service_costs(ce, table, start, end)
    ingest_tag_costs(ce, table, start, end)
    ingest_coverage(ce, table, start, end)
    scan_waste(ec2, table)
    scan_tag_compliance(tagging, table)

    return {"statusCode": 200, "message": "Ingestion complete", "period": f"{start} → {end}"}
