data "aws_ssoadmin_instances" "this" {
  provider = aws.idc
}

locals {
  idc_instance_arn  = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
}

data "aws_identitystore_group" "argocd_admin" {
  provider          = aws.idc
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = var.argocd_admin_sso_group_name
    }
  }
}

module "argocd_capability" {
  source  = "terraform-aws-modules/eks/aws//modules/capability"
  version = "~> 21.15"

  name         = "argocd"
  cluster_name = module.eks.cluster_name
  type         = "ARGOCD"

  configuration = {
    argo_cd = {
      aws_idc = {
        idc_instance_arn = local.idc_instance_arn
        idc_region       = var.idc_region
      }
      namespace = "argocd"
      rbac_role_mapping = [{
        role = "ADMIN"
        identity = [{
          id   = data.aws_identitystore_group.argocd_admin.group_id
          type = "SSO_GROUP"
        }]
      }]
    }
  }

  tags = local.tags
}
