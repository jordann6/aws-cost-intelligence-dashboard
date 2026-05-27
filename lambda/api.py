import json
import os
import boto3
from decimal import Decimal
from datetime import date, timedelta
from boto3.dynamodb.conditions import Key

CORS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET,OPTIONS",
}


class _Enc(json.JSONEncoder):
    def default(self, o):
        return float(o) if isinstance(o, Decimal) else super().default(o)


def ok(data):
    return {
        "statusCode": 200,
        "headers": {**CORS, "Content-Type": "application/json"},
        "body": json.dumps(data, cls=_Enc),
    }


def handler(event, context):
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {"statusCode": 200, "headers": CORS, "body": ""}

    table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
    path = event.get("rawPath", "/")

    if path == "/costs":
        today = date.today().strftime("%Y-%m-%d")
        start = (date.today() - timedelta(days=30)).strftime("%Y-%m-%d")
        resp = table.query(
            KeyConditionExpression=Key("pk").eq("DAILY") & Key("sk").between(f"{start}#", f"{today}#~")
        )
        return ok(resp.get("Items", []))

    if path == "/anomalies":
        today = date.today().strftime("%Y-%m-%d")
        start = (date.today() - timedelta(days=7)).strftime("%Y-%m-%d")
        resp = table.query(
            KeyConditionExpression=Key("pk").eq("ANOMALY") & Key("sk").between(f"{start}#", f"{today}#~")
        )
        return ok(resp.get("Items", []))

    if path == "/forecast":
        resp = table.query(
            KeyConditionExpression=Key("pk").eq("FORECAST")
        )
        return ok(resp.get("Items", []))

    if path == "/tags":
        resp = table.query(
            KeyConditionExpression=Key("pk").eq("TAG_ISSUE"),
            Limit=100,
        )
        return ok(resp.get("Items", []))

    return {
        "statusCode": 404,
        "headers": {**CORS, "Content-Type": "application/json"},
        "body": json.dumps({"error": "not found"}),
    }
