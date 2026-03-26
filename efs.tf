#---------------------------------------------------------------
# AWS EFS Module: Shared Persistent Storage for Model Caching
#
# This module provisions an Amazon EFS (Elastic File System)
# with mount targets across availability zones. It is used as
# ReadWriteMany shared storage for NIMCache, allowing cached
# models to persist across pod restarts and be reused by multiple
# NIMService pods for faster startup and reduced cold boot latency.
#---------------------------------------------------------------
module "efs" {
  source  = "terraform-aws-modules/efs/aws"
  version = "~> 2.2"

  creation_token = local.name
  name           = local.name

  # Mount targets / security group
  mount_targets = {
    for k, v in zipmap(local.azs, module.vpc.private_subnets) : k => { subnet_id = v }
  }
  security_group_description = "${local.name} EFS security group"
  security_group_vpc_id      = module.vpc.vpc_id
  security_group_ingress_rules = {
    vpc = {
      description = "NFS ingress from VPC private subnets"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }

  tags = local.tags
}
#---------------------------------------------------------------
# Kubernetes StorageClass for Dynamic EFS Provisioning
#
# This StorageClass enables dynamic provisioning of EFS volumes
# using the AWS EFS CSI driver. It is used by NIMCache CRD to create
# a PersistentVolumeClaim (PVC) with ReadWriteMany access mode,
# essential for sharing cached models between GPU pods in NIMService.
#---------------------------------------------------------------
resource "kubernetes_storage_class_v1" "efs" {
  metadata {
    name = "efs-sc-dynamic"
  }

  storage_provisioner = "efs.csi.aws.com"
  parameters = {
    provisioningMode = "efs-ap" # Dynamic provisioning
    fileSystemId     = module.efs.id
    directoryPerms   = "755"
  }

  mount_options = [
    "iam"
  ]

  depends_on = [
    module.eks_blueprints_addons.aws_efs_csi_driver
  ]
}
