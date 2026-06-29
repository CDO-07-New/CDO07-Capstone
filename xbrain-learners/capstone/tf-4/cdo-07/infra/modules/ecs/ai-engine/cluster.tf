# =============================================================================
# ECS Cluster — AI Engine (tf-4-aiops-cluster)
# =============================================================================
# Contract: Deployment Contract §Compute — Cluster = "tf-4-aiops-cluster"
# Note:     Separate cluster from mock-services to isolate AI Engine workload.
#           Pattern mirrors modules/ecs/mock-services/cluster.tf
# =============================================================================

locals {
  cluster_name = "${var.environment}-tf-4-aiops-cluster"
}

module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 5.0"

  cluster_name = local.cluster_name

  # Fargate capacity providers
  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 100
      }
    }
  }

  tags = var.tags
}
