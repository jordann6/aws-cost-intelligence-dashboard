from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import Lambda
from diagrams.aws.database import Dynamodb
from diagrams.aws.integration import Eventbridge, SNS
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
    scheduler = Eventbridge("EventBridge Scheduler\nIngest 01:00 · Analyze 02:00 UTC")

    with Cluster("AWS · us-east-1"):

        with Cluster("Data Pipeline"):
            ingester = Lambda("Ingester Lambda\nCost Explorer API\nTag Compliance Scan")
            analyzer = Lambda("Analyzer Lambda\nZ-Score Anomaly Detection\n14-Day Linear Regression")

        db = Dynamodb("DynamoDB\nSingle Table\nDAILY · ANOMALY · FORECAST · TAG_ISSUE")
        alerts = SNS("SNS Topic\nAnomaly Alerts")

        with Cluster("API Layer"):
            apigw = APIGateway("API Gateway\nHTTP API · CORS Enabled\n/costs  /anomalies  /forecast  /tags")
            api_fn = Lambda("API Lambda\nREST Handler")

        with Cluster("React Frontend"):
            cf = CloudFront("CloudFront\nOAC · HTTPS Redirect\nSPA Fallback")
            s3_ui = S3("S3 Bucket\nStatic Assets")

    scheduler >> Edge(label="01:00 UTC") >> ingester
    scheduler >> Edge(label="02:00 UTC") >> analyzer
    ingester >> Edge(label="write") >> db
    analyzer >> Edge(label="read / write") >> db
    analyzer >> Edge(label="anomaly alert") >> alerts
    db >> Edge(label="read") >> api_fn
    apigw >> api_fn
    cf >> s3_ui
    cf >> Edge(label="VITE_API_URL") >> apigw
