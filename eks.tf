################################################################################
# Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.name
  cluster_version = "1.34"

  # Give the Terraform identity admin access to the cluster
  # which will allow it to deploy resources into the cluster
  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true

  cluster_addons = {
    # Enable after creation to run on Karpenter managed nodes
    vpc-cni = {
      enabled     = true
      most_recent = true
      # addon_version               = "v1.19.6-eksbuild.7"
      resolve_conflicts_on_update = "OVERWRITE"
      before_compute              = true
      configuration_values = jsonencode({
        # enableNetworkPolicy : "true"
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
          # ENABLE_POD_ENI           = "true"
        }
      })
    }
    coredns = {
      enabled                     = true
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
      configuration_values = jsonencode({
        nodeSelector = {
          "eks.amazonaws.com/compute-type" = "fargate"
        }
        autoScaling = {
          enabled     = true
          minReplicas = 2
          maxReplicas = 10
        }
        corefile = <<-EOF
          .:53 {
              errors
              health {
                  lameduck 10s
              }
              ready
              kubernetes cluster.local in-addr.arpa ip6.arpa {
                  pods insecure
                  fallthrough in-addr.arpa ip6.arpa
                  ttl 30
              }
              prometheus :9153
              forward . /etc/resolv.conf
              cache 30
              loop
              reload
              loadbalance
          }
        EOF
      })
    }
    kube-proxy = {
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
      configuration_values = jsonencode({
        mode = "ipvs"
        ipvs = {
          scheduler = "rr"
        }
      })
    }
    eks-pod-identity-agent = { most_recent = true }
  }

  # For migration to EKS Auto Mode only
  # bootstrap_self_managed_addons = true
  # cluster_compute_config = {
  #   enabled    = true
  #   node_pools = ["general-purpose", "system"]
  # }
  enable_efa_support = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Fargate profiles use the cluster primary security group
  # Therefore these are not used and can be skipped
  create_cluster_security_group = false
  create_node_security_group    = false

  fargate_profiles = {
    karpenter = {
      selectors = [
        { namespace = "karpenter" }
      ]
    }
    coredns = {
      selectors = [
        { namespace = "kube-system"
          labels = {
            k8s-app = "kube-dns"
          }
        }
      ]
    }
  }

  # # Add the EFA security group to the node security group
  # node_security_group_additional_rules = {
  #   efa_all = {
  #     description = "Allow all traffic for EFA communication"
  #     protocol    = "-1"
  #     from_port   = 0
  #     to_port     = 0
  #     type        = "ingress"
  #     self        = true
  #   }
  # }

  eks_managed_node_groups = {

    ng-1 = {
      create         = false
      min_size       = 1
      max_size       = 2
      desired_size   = 2
      instance_types = ["m5.xlarge"]
      capacity_type  = "SPOT"
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 800
            volume_type = "gp3"
            iops        = 3000
            throughput  = 150
            # encrypted             = true
            # kms_key_id            = module.ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
      }
      key_name = "mac-ed25519"
      tags = {
        "test" = "1"
      }
    }

    p5-cbr = {
      create = false
      # The EKS AL2023 NVIDIA AMI provides all of the necessary components
      # for accelerated workloads w/ EFA
      ami_type       = "AL2023_x86_64_NVIDIA"
      instance_types = ["p5.4xlarge"]

      # Mount instance store volumes in RAID-0 for kubelet and containerd
      # https://github.com/awslabs/amazon-eks-ami/blob/master/doc/USER_GUIDE.md#raid-0-for-kubelet-and-containerd-raid0
      cloudinit_pre_nodeadm = [
        {
          content_type = "application/node.eks.aws"
          content      = <<-EOT
            ---
            apiVersion: node.eks.aws/v1alpha1
            kind: NodeConfig
            spec:
              instance:
                localStorage:
                  strategy: RAID0
          EOT
        }
      ]

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 800
            volume_type = "gp3"
            iops        = 3000
            throughput  = 150
            # encrypted             = true
            # kms_key_id            = module.ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
      }
      node_repair_config = {
        enabled = false
      }

      min_size     = 0
      max_size     = 2
      desired_size = 1

      # This will:
      # 1. Create a placement group to place the instances close to one another
      # 2. Ignore subnets that reside in AZs that do not support the instance type
      # 3. Expose all of the available EFA interfaces on the launch template
      enable_efa_support = false

      labels = {
        "vpc.amazonaws.com/efa.present" = "true"
        "nvidia.com/gpu.present"        = "true"
      }

      taints = {
        # Ensure only GPU workloads are scheduled on this node group
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }

      # First subnet is in the "${local.region}a" availability zone
      # where the capacity reservation is created
      # TODO - Update the subnet to match the availability zone of *YOUR capacity reservation
      subnet_ids = module.vpc.private_subnets

      # ML capacity block reservation
      capacity_type = "CAPACITY_BLOCK"
      instance_market_options = {
        market_type = "capacity-block"
      }
      capacity_reservation_specification = {
        capacity_reservation_target = {
          capacity_reservation_id = var.capacity_reservation_id
        }
      }
    }
  }

  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.name
  })
}


# output "eks_module_name" {
#   value = module.eks
# }



import {
  to = module.eks.aws_eks_access_entry.this["cluster_creator"]
  id = "${local.name}:arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/Admin"
}
#---------------------------------------------------------------
# Disable default GP2 Storage Class
#---------------------------------------------------------------
resource "kubernetes_annotations" "disable_gp2" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  force = true

  depends_on = [module.eks.eks_cluster_id]
}
#---------------------------------------------------------------
# GP3 Storage Class - Set as default
#---------------------------------------------------------------
resource "kubernetes_storage_class" "default_gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    type = "gp3"
  }

  depends_on = [
    module.eks.eks_cluster_id,
    kubernetes_annotations.disable_gp2
  ]
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name} --alias ${local.name}"
}
