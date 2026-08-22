from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import Lambda
from diagrams.aws.database import Dynamodb
from diagrams.aws.integration import Eventbridge, SNS
from diagrams.aws.cost import CostExplorer, Budgets
from diagrams.aws.network import APIGateway, CloudFront
from diagrams.aws.storage import S3

graph_attrs = {
    "fontsize": "13",
    "bgcolor": "white",
    "pad": "0.6",
    "splines": "ortho",
    "nodesep": "0.6",
    "ranksep": "0.8",
}

node_attrs = {
    "fontsize": "11",
}

with Diagram(
    "AWS Cost Intelligence Dashboard",
    filename="docs/architecture",
    outformat="png",
    show=False,
    direction="TB",
    graph_attr=graph_attrs,
    node_attr=node_attrs,
):
    scheduler = Eventbridge("EventBridge Scheduler\nLLM 00:30 · Ingest 01:00 · Analyze 02:00 UTC")

    with Cluster("External · LLM Gateway"):
        llm_db = Dynamodb("DynamoDB\nrequest-log table\nprovider · estimated_cost_cents")

    with Cluster("AWS · us-east-1"):

        with Cluster("Cost & Optimization Sources"):
            ce = CostExplorer("Cost Explorer\nby service · by TAG:Project\nRI / Savings Plans coverage")
            budget = Budgets("AWS Budgets\n80% actual · 100% forecast")

        with Cluster("Data Pipeline"):
            llm_ingester = Lambda("LLM Ingester Lambda\nAggregates LLM API spend\nby provider from gateway")
            ingester = Lambda("Ingester Lambda\nService + tag-grouped cost\nCoverage · Waste scan · Tag compliance")
            analyzer = Lambda("Analyzer Lambda\nZ-Score Anomaly Detection\n14-Day Linear Regression")

        db = Dynamodb("DynamoDB\nSingle Table\nDAILY · DAILY_TAG · COVERAGE\nWASTE · ANOMALY · FORECAST · TAG_ISSUE")
        alerts = SNS("SNS Topic\nAnomaly + Budget Alerts")

        with Cluster("API Layer"):
            apigw = APIGateway("API Gateway · HTTP API · CORS\n/costs /costs-by-tag /coverage\n/waste /anomalies /forecast /tags")
            api_fn = Lambda("API Lambda\nREST Handler")

        with Cluster("React Frontend"):
            cf = CloudFront("CloudFront\nOAC · HTTPS Redirect\nSPA Fallback")
            s3_ui = S3("S3 Bucket\nStatic Assets")

    scheduler >> Edge(label="00:30 UTC") >> llm_ingester
    scheduler >> Edge(label="01:00 UTC") >> ingester
    scheduler >> Edge(label="02:00 UTC") >> analyzer
    llm_db >> Edge(label="scan") >> llm_ingester
    ce >> Edge(label="cost + coverage") >> ingester
    llm_ingester >> Edge(label="write LLM/Provider") >> db
    ingester >> Edge(label="write") >> db
    analyzer >> Edge(label="read / write") >> db
    analyzer >> Edge(label="anomaly alert") >> alerts
    budget >> Edge(label="threshold breach", color="firebrick") >> alerts
    db >> Edge(label="read") >> api_fn
    apigw >> api_fn
    cf >> s3_ui
    cf >> Edge(label="VITE_API_URL") >> apigw
