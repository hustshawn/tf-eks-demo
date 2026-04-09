module "s3_files" {
  source  = "hustshawn/s3-files/aws"
  version = "~> 1.0"

  name            = local.name
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
  azs             = local.azs
  source_sg_id    = module.eks.cluster_primary_security_group_id

  create_storage_class    = true
  storage_class_name      = "s3-files"

  tags = local.tags

  # Ensure the EFS CSI driver Helm release is ready before the StorageClass is created
  depends_on = [module.eks_blueprints_addons.aws_efs_csi_driver]
}
