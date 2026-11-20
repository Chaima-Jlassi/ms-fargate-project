"""Generates the three architecture diagrams in docs/.

    docs/architecture.png   overall solution
    docs/network.png        VPC / subnet / AZ layout (matches infra/network.tf)
    docs/cicd.png           build and blue/green deployment flow

Usage (from the repository root):
    pip install diagrams      # also needs Graphviz installed
    python3 docs/generate_diagrams.py
"""
from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import ECR, Fargate
from diagrams.aws.database import ElasticacheForRedis
from diagrams.aws.devtools import Codedeploy, Codepipeline, XRay
from diagrams.aws.management import Cloudwatch
from diagrams.aws.network import (
    ALB,
    CloudMap,
    InternetGateway,
    NATGateway,
    PrivateSubnet,
    PublicSubnet,
)
from diagrams.aws.security import SecretsManager
from diagrams.aws.storage import S3
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.client import User, Users
from diagrams.onprem.vcs import Github

BASE = {
    "fontsize": "22",
    "labelloc": "t",
    "pad": "0.5",
    "nodesep": "0.7",
    "ranksep": "1.1",
    "splines": "spline",
}


def architecture():
    with Diagram(
        "Containerized Microservices on ECS Fargate",
        filename="docs/architecture",
        outformat="png",
        show=False,
        direction="LR",
        graph_attr=dict(BASE, nodesep="0.5", ranksep="0.9"),
    ):
        users = Users("Internet users")

        with Cluster("GitHub"):
            repo = Github("GitHub repo")
            gha = GithubActions("GitHub Actions\ntest, build, scan")
            repo >> gha

        with Cluster("AWS Region (eu-north-1)"):
            ecr = ECR("ECR\nscan on push")
            secrets = SecretsManager("Secrets Manager\nJWT secret")
            pipeline = Codepipeline("CodePipeline")
            deploy = Codedeploy("CodeDeploy\nblue/green + rollback")
            pipeline >> deploy

            with Cluster("VPC 10.0.0.0/16"):
                igw = InternetGateway("Internet Gateway")

                with Cluster("Public subnets (2 AZs)"):
                    alb = ALB("Application\nLoad Balancer")
                    nat = NATGateway("NAT Gateway")

                with Cluster("Private subnets (2 AZs)"):
                    cloudmap = CloudMap("Cloud Map\nprivate DNS (*.local)")

                    with Cluster("ECS cluster (Fargate)"):
                        auth = Fargate("auth")
                        orders = Fargate("orders")
                        notif = Fargate("notifications")

                    redis = ElasticacheForRedis("ElastiCache Redis\nshared sessions")

            cw = Cloudwatch("CloudWatch\nlogs, alarms")
            xray = XRay("X-Ray\nservice map")

        # Ingress: one ALB listener, path-based rules
        users >> igw >> alb
        alb >> Edge(label="/auth/*") >> auth
        alb >> Edge(label="/orders*") >> orders
        alb >> Edge(label="/notify*, /notifications*") >> notif

        # Service-to-service calls resolve through Cloud Map
        orders >> Edge(label="verify token\nauth.local", style="dashed") >> auth
        orders >> Edge(label="notify\nnotifications.local", style="dashed") >> notif
        cloudmap >> Edge(style="dotted", color="gray") >> orders

        # Data and secrets
        auth >> Edge(label="sessions") >> redis
        secrets >> Edge(label="injected at\ntask start", style="dotted") >> auth

        # Images and releases
        gha >> Edge(taillabel="push image (OIDC)", labeldistance="3", labelangle="-20") >> ecr
        ecr >> Edge(label="image push\nevent", style="dashed") >> pipeline
        nat >> Edge(label="pull image", style="dotted") >> ecr
        deploy >> Edge(taillabel="shift traffic", labeldistance="3", labelangle="20") >> alb

        # Observability
        notif >> Edge(style="dotted", color="darkgreen") >> cw
        orders >> Edge(style="dotted", color="darkgreen") >> xray


def network():
    attrs = dict(BASE, nodesep="0.6", ranksep="1.2")
    with Diagram(
        "Network layout: VPC 10.0.0.0/16, two Availability Zones",
        filename="docs/network",
        outformat="png",
        show=False,
        direction="LR",
        graph_attr=attrs,
    ):
        users = Users("Internet")
        igw = InternetGateway("Internet Gateway")

        with Cluster("VPC 10.0.0.0/16"):
            with Cluster("Availability Zone A"):
                with Cluster("Public subnet 10.0.0.0/24"):
                    alb_a = ALB("ALB node")
                    nat = NATGateway("NAT Gateway\n(single, shared)")
                with Cluster("Private subnet 10.0.10.0/24"):
                    tasks_a = Fargate("Fargate tasks\nSG: 3000 from ALB")
                    redis = ElasticacheForRedis("Redis\nSG: 6379 from tasks")

            with Cluster("Availability Zone B"):
                with Cluster("Public subnet 10.0.1.0/24"):
                    alb_b = ALB("ALB node")
                with Cluster("Private subnet 10.0.11.0/24"):
                    tasks_b = Fargate("Fargate tasks\nSG: 3000 from ALB")

        users >> igw
        igw >> Edge(label="80") >> alb_a
        igw >> Edge(label="80") >> alb_b
        alb_a >> Edge(label="3000") >> tasks_a
        alb_b >> Edge(label="3000") >> tasks_b
        tasks_a >> Edge(label="6379") >> redis
        tasks_b >> Edge(label="6379") >> redis
        tasks_a >> Edge(label="outbound", style="dashed") >> nat
        tasks_b >> Edge(label="outbound (cross-AZ)", style="dashed") >> nat


def cicd():
    with Diagram(
        "CI/CD: build, scan and blue/green deployment",
        filename="docs/cicd",
        outformat="png",
        show=False,
        direction="LR",
        graph_attr=BASE,
    ):
        dev = User("Developer")
        repo = Github("GitHub repo\n(push to main)")

        with Cluster("Continuous integration"):
            gha = GithubActions("GitHub Actions\ntest, build, Trivy scan")

        with Cluster("AWS"):
            ecr = ECR("ECR\nscan on push")
            template = S3("S3\ntaskdef + appspec")
            pipeline = Codepipeline("CodePipeline\n(one per service)")
            deploy = Codedeploy("CodeDeploy\nECS blue/green")
            alarms = Cloudwatch("CloudWatch alarm\n5xx errors")

            with Cluster("ECS service"):
                blue = Fargate("blue tasks\n(current version)")
                green = Fargate("green tasks\n(new version)")

            alb = ALB("ALB\nlistener :80")

        dev >> repo >> gha
        gha >> Edge(label="1. push image\n(OIDC, no stored keys)") >> ecr
        ecr >> Edge(label="2. image push event") >> pipeline
        template >> Edge(label="taskdef + appspec") >> pipeline
        pipeline >> Edge(label="3. start deployment") >> deploy
        deploy >> Edge(label="4. start green") >> green
        deploy >> Edge(label="5. shift traffic\n(canary 10%, 5 min)") >> alb
        alb >> Edge(label="live") >> blue
        alb >> Edge(label="after shift", style="dashed") >> green
        alarms >> Edge(label="6. alarm: rollback", color="firebrick") >> deploy


if __name__ == "__main__":
    architecture()
    network()
    cicd()
    print("Generated docs/architecture.png, docs/network.png, docs/cicd.png")
