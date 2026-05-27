from diagrams import Diagram, Cluster, Edge
from diagrams.aws.storage import S3
from diagrams.aws.compute import Lambda
from diagrams.aws.integration import Eventbridge, SNS
from diagrams.aws.security import IAM
from diagrams.aws.database import Dynamodb
from diagrams.aws.network import APIGateway, CloudFront

graph_attrs = {
    "fontsize": "13",
    "bgcolor": "white",
    "pad": "0.5",
    "splines": "ortho",
}

node_attrs = {
    "fontsize": "11",
}

with Diagram(
    "AWS Cost Intelligence Dashboard",
    filename="docs/architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attrs,
    node_attr=node_attrs,
):
    scheduler = Eventbridge("EventBridge Scheduler\n01:00 Ingest / 02:00 Analyze")

    with Cluster("AWS · us-east-1"):
        ingester = Lambda("Ingester\nCost Explorer + Tag Scan")
        analyzer = Lambda("Analyzer\nZ-Score + Forecast")
        api_fn = Lambda("API\nREST Handler")

        db = Dynamodb("DynamoDB\nSingle Table")
        alerts = SNS("SNS\nAnomaly Alerts")
        apigw = APIGateway("API Gateway\nHTTP API")

        with Cluster("React Frontend"):
            cf = CloudFront("CloudFront")
            s3_ui = S3("S3\nStatic Assets")

    scheduler >> ingester >> db
    scheduler >> analyzer
    analyzer >> db
    analyzer >> alerts
    db >> api_fn
    apigw >> api_fn
    cf >> s3_ui
    apigw << Edge(label="VITE_API_URL") << cf
