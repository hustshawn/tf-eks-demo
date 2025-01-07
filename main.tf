terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9"
    }
  }

  ##  Used for end-to-end testing on project; update to suit your needs
  backend "s3" {
    bucket  = "tf-eks-remote-states"
    region  = "ap-southeast-1"
    key     = "e2e/tf-eks-demo/terraform.tfstate"
    profile = "account-a"
  }
}

provider "aws" {
  region = local.region
}

# This provider is required for ECR to authenticate with public repos. Please note ECR authentication requires us-east-1 as region hence its hardcoded below.
# If your region is same as us-east-1 then you can just use one aws provider
provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

################################################################################
# Common data/locals
################################################################################

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

data "aws_availability_zones" "available" {
  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}


data "aws_route53_zone" "selected" {
  name = local.domain
  # private_zone = true
}

data "aws_acm_certificate" "issued" {
  domain   = local.acm_wildcard_domain
  statuses = ["ISSUED"]
}

locals {
  name   = "tf-eks-demo"
  region = var.region

  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  domain              = var.dns_domain
  acm_wildcard_domain = "*.${var.dns_domain}"
  grafana_host        = "grafana.${var.dns_domain}"
  argocd_host         = "argocd.${var.dns_domain}"

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}
