data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Project     = "eks-secure-baseline"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

################################################################################
# Network: private nodes, NAT egress, flow logs, default SG locked down
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.9.0"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, 48 + i)]
  intra_subnets   = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, 52 + i)]

  enable_nat_gateway = true
  single_nat_gateway = true # dev cost saving; one per AZ in prod

  # Default SG with no rules, so nothing is accidentally open
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  # VPC flow logs to CloudWatch for audit/incident response
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_max_aggregation_interval               = 60
  flow_log_cloudwatch_log_group_retention_in_days = 90

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

################################################################################
# EKS: envelope-encrypted secrets, full audit logging, access entries (no
# aws-auth ConfigMap), Pod Identity, VPC CNI NetworkPolicy enforcement
################################################################################

resource "aws_kms_key" "eks" {
  description             = "${var.name} EKS secrets envelope encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.30.2"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  endpoint_private_access      = true
  endpoint_public_access       = length(var.api_allowed_cidrs) > 0
  endpoint_public_access_cidrs = var.api_allowed_cidrs

  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = 90

  create_kms_key = false
  encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries = {
    for i, arn in var.admin_role_arns : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  addons = {
    coredns    = {}
    kube-proxy = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
  }

  eks_managed_node_groups = {
    general = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = ["t3.large"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required" # IMDSv2 only
        http_put_response_hop_limit = 1          # pods cannot reach node IMDS
      }

      block_device_mappings = {
        xvdb = {
          device_name = "/dev/xvdb"
          ebs = {
            volume_size = 50
            volume_type = "gp3"
            encrypted   = true
          }
        }
      }
    }
  }
}

################################################################################
# Workload storage + least-privilege access through Pod Identity
################################################################################

module "artifacts_bucket" {
  source = "../../modules/s3-secure-bucket"

  name = "${var.name}-artifacts-${data.aws_caller_identity.current.account_id}"
}

data "aws_iam_policy_document" "app_s3" {
  statement {
    sid       = "ListOwnPrefix"
    actions   = ["s3:ListBucket"]
    resources = [module.artifacts_bucket.bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["reports/*"]
    }
  }

  statement {
    sid       = "ReadWriteOwnPrefix"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${module.artifacts_bucket.bucket_arn}/reports/*"]
  }

  statement {
    sid       = "UseBucketKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [module.artifacts_bucket.kms_key_arn]
  }
}

module "report_writer_identity" {
  source = "../../modules/pod-identity-role"

  role_name       = "${var.name}-report-writer"
  cluster_name    = module.eks.cluster_name
  cluster_arn     = module.eks.cluster_arn
  account_id      = data.aws_caller_identity.current.account_id
  namespace       = "security"
  service_account = "vuln-reporter"
  policy_json     = data.aws_iam_policy_document.app_s3.json
}

################################################################################
# CI/CD: keyless GitHub Actions deploy role, scoped to one repo + environment
################################################################################

data "aws_iam_policy_document" "ci_deploy" {
  statement {
    sid       = "DescribeCluster"
    actions   = ["eks:DescribeCluster"]
    resources = [module.eks.cluster_arn]
  }

  statement {
    sid = "PushImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = ["arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${var.name}/*"]
  }

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource-level permissions
  }
}

module "github_deploy_role" {
  source = "../../modules/github-oidc-role"

  role_name          = "${var.name}-github-deploy"
  allowed_subjects   = var.github_subjects
  inline_policy_json = data.aws_iam_policy_document.ci_deploy.json
}
