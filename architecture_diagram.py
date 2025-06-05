from diagrams import Diagram, Cluster, Edge
from diagrams.aws.storage import S3
from diagrams.aws.analytics import Glue, Athena, LakeFormation
from diagrams.aws.integration import StepFunctions
from diagrams.aws.compute import Lambda
from diagrams.aws.security import KMS

graph_attr = {
    "fontsize": "45",
    "bgcolor": "white",
    "splines": "curved",
    "pad": "1.0"
}

edge_attr = {
    "fontsize": "18",
    "fontcolor": "#2D3436",
    "color": "#2D3436",
    "penwidth": "1.5",
    "arrowsize": "1.2"
}

with Diagram("AWS Data Lake Pipeline", show=False, direction="LR", graph_attr=graph_attr):
    with Cluster("Data Lake Storage", graph_attr={
        "fontsize": "20",
        "size": "20,20",
        "margin": "50",
        "pad": "1.0",
        "label": "Process Data",
        "labeljust": "t",
        "labelloc": "t"
    }):
        raw_data = S3("Raw Data Bucket")
        artifacts = S3("Artifacts Bucket")
        s3_tables = S3("S3 Tables Bucket")

    with Cluster("Orchestration & Compute", graph_attr={"margin": "40", "pad": "2.0", "fontsize": "20"}):
        lambda_fn = Lambda("Trigger Step Function")
        step_fn = StepFunctions("ETL State Machine")
        glue_job = Glue("Glue Job \n (csv_to_iceberg.py)")

    with Cluster("Catalog & Security", graph_attr={"margin": "40", "pad": "2.0", "fontsize": "20"}):
        lakeformation = LakeFormation("Lake Formation")
        kms = KMS("KMS Key")

    athena = Athena("Athena")

    raw_data >> Edge(label="S3 Event", **edge_attr) >> lambda_fn
    lambda_fn >> Edge(label="Trigger", **edge_attr) >> step_fn
    step_fn >> Edge(label="Start Job", **edge_attr) >> glue_job
    glue_job >> Edge(label="Write Iceberg Table", **edge_attr) >> s3_tables
    glue_job >> Edge(label="Get Artifacts \n & Jars", **edge_attr) >> artifacts

    s3_tables >> Edge(label="Access Control & \n Catalog", **edge_attr) >> lakeformation
    s3_tables >> Edge(label="Encrypt Data", **edge_attr) >> kms
    s3_tables >> Edge(label="Expose Data", **edge_attr) >> athena