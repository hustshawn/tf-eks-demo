################################################################################
# Temporary standalone private subnet in us-west-2d
#
# The VPC module (vpc.tf) only builds subnets across the first 3 AZs
# (slice(azs, 0, 3) => 2a/2b/2c). P5en on-demand capacity is frequently only
# available in us-west-2d, which the VPC does not otherwise reach.
#
# This adds ONE extra private subnet in 2d, decoupled from the module so it can
# be removed cleanly later. It reuses the module's existing private route table
# (single NAT in 2a), so egress from 2d crosses AZ to that NAT — acceptable for
# occasional model-weight pulls; add a dedicated 2d NAT if that cost matters.
#
# Tags:
#   karpenter.sh/discovery = <cluster>   -> Karpenter launches nodes here
#   kubernetes.io/role/cni = 1           -> VPC CNI may allocate Pod IPs here
#   kubernetes.io/role/internal-elb = 1  -> matches the other private subnets
################################################################################

locals {
  # 4th AZ in the region (sorted): us-west-2d. Same data source the module uses.
  az_2d = data.aws_availability_zones.available.names[3]

  # cidrsubnet(10.6.0.0/16, 4, 4) = 10.6.64.0/20.
  # Index 3 (10.6.48.0/20) is skipped: it overlaps the public subnets
  # (10.6.48.0/24, .49.0/24, .50.0/24) created by the module.
  subnet_2d_cidr = cidrsubnet(local.vpc_cidr, 4, 4)
}

resource "aws_subnet" "private_2d" {
  vpc_id            = module.vpc.vpc_id
  availability_zone = local.az_2d
  cidr_block        = local.subnet_2d_cidr

  tags = merge(local.tags, {
    "Name"                            = "${local.name}-private-${local.az_2d}"
    "karpenter.sh/discovery"          = local.name
    "kubernetes.io/role/cni"          = "1"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_route_table_association" "private_2d" {
  subnet_id      = aws_subnet.private_2d.id
  route_table_id = module.vpc.private_route_table_ids[0]
}
