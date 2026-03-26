module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.23"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn
  # disable the Telemetry from AWS using CloudFormation
  observability_tag = null

  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
      configuration_values = jsonencode({
        "controller" : {
          "volumeModificationFeature" : {
            "enabled" : true
          }
        },
        "sidecars" : {
          "snapshotter" : {
            "forceEnable" : true
          }
        }
      })
    }
    aws-efs-csi-driver           = { most_recent = true }
    metrics-server               = { most_recent = true }
    aws-mountpoint-s3-csi-driver = { most_recent = true }
    # amazon-cloudwatch-observability   = { most_recent = true }
    aws-network-flow-monitoring-agent = {
      most_recent = true
      pod_identity_association = [{
        role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKSPodIdentityAWSNetworkFlowMonitorAgentRole"
        service_account = "aws-network-flow-monitor-agent-service-account"
      }]
    }
    # eks-node-monitoring-agent       = { most_recent = true }
  }

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    chart_version = "3.1.0"
    set = [
      {
        name  = "vpcId" # explicitly set the vpcId, otherwise it may not able to retrieve the vpcId from the node
        value = module.vpc.vpc_id
      },
      # ALBGatewayAPI and NLBGatewayAPI feature gates removed — Gateway API is GA in v3.x
    ]
  }
  enable_aws_efs_csi_driver = false

  # EKS Managed Addons included metrics-server

  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    values = [
      templatefile("${path.module}/kubernetes/kube-prometheus-stack/values.override.yaml", {
        ingressClassName = "alb"
        grafana_host     = local.grafana_host
        acm_cert_arn     = data.aws_acm_certificate.issued.arn
        slack_api_url    = var.slack_api_url
      })
    ]
  }

  enable_external_dns            = true
  external_dns_route53_zone_arns = [data.aws_route53_zone.selected.arn] # need the zone arns to create role
  enable_cert_manager            = true
  # cert_manager_route53_hosted_zone_arns  = ["arn:aws:route53:::hostedzone/XXXXXXXXXXXXX"]

  enable_ingress_nginx = true
  ingress_nginx = {
    chart_version = "4.12.1"
    values = [templatefile("${path.module}/kubernetes/ingress-nginx/custom-values.yaml", {
      ssl_cert_arn = data.aws_acm_certificate.issued.arn
    })]
  }

  enable_argocd = true
  argocd = {
    values = [templatefile("${path.module}/kubernetes/argocd/values.override.yaml", {
      hostname     = local.argocd_host
      acm_cert_arn = data.aws_acm_certificate.issued.arn
    })]
    # set_values = [
    set = [
      {
        name  = "server.extraArgs[0]"
        value = "--insecure"
      }
    ]
  }

  helm_releases = {
    # nvidia-device-plugin = {
    #   description      = "A Helm chart for NVIDIA Device Plugin"
    #   namespace        = "nvidia-device-plugin"
    #   create_namespace = true
    #   chart            = "nvidia-device-plugin"
    #   chart_version    = "0.17.0"
    #   repository       = "https://nvidia.github.io/k8s-device-plugin"
    #   values           = [file("${path.module}/kubernetes/nvidia-device-plugin/values.yaml")]
    # },
    prometheus-adapter = {
      description      = "A Helm chart for Prometheus Adapter"
      namespace        = "prometheus-adapter"
      create_namespace = true
      chart            = "prometheus-adapter"
      chart_version    = "4.10.0"
      repository       = "https://prometheus-community.github.io/helm-charts"
      values = [
        <<-EOT
        prometheus:
          url: "http://kube-prometheus-stack-prometheus.kube-prometheus-stack.svc"
          port: "9090"
        EOT
      ]
    }
  }

  tags = local.tags
}


module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.7"

  name                      = "ebs-csi"
  attach_aws_ebs_csi_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }

  tags = local.tags
}

module "efs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.7"

  name                      = "efs-csi"
  attach_aws_efs_csi_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "efs-csi-controller-sa"
    }
  }

  tags = local.tags
}

module "s3_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.7"

  name                               = "s3-csi"
  attach_mountpoint_s3_csi_policy    = true
  mountpoint_s3_csi_bucket_arns      = ["arn:aws:s3:::*"]
  mountpoint_s3_csi_bucket_path_arns = ["arn:aws:s3:::*"]
  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "s3-csi-driver-sa"
    }
  }

  tags = local.tags
}

module "aws_cloudwatch_observability_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.7"

  name = "aws-cloudwatch-observability"

  attach_aws_cloudwatch_observability_policy = true
  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "amazon-cloudwatch"
      service_account = "cloudwatch-agent"
    }
  }

  tags = local.tags
}


resource "helm_release" "nvidia_gpu_operator" {
  count      = var.enable_nvidia_device_plugin ? 1 : 0 # Reusing the same variable for now
  name       = "gpu-operator"
  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "gpu-operator"
  # version          = "v25.10.1" 
  version          = "v26.3.0" # Latest stable version as of now
  namespace        = "gpu-operator"
  create_namespace = true
  wait             = true

  values = [templatefile("${path.module}/kubernetes/gpu-operator/values-override.yaml", {})]
}

resource "helm_release" "aws_efa_device_plugin" {
  count = var.enable_aws_efa_device_plugin ? 1 : 0
  name  = "aws-efa-k8s-device-plugin"
  # https://github.com/aws/eks-charts/tree/master/stable/aws-efa-k8s-device-plugin
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-efa-k8s-device-plugin"
  version    = "v0.5.7"
  namespace  = "kube-system"
  wait       = false

  values = [
    <<-EOT
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node.kubernetes.io/instance-type
                operator: In
                values:
                # P4 family
                - p4d.24xlarge
                - p4de.24xlarge
                # P5 family
                - p5.48xlarge
                - p5e.48xlarge
                - p5en.48xlarge
                # P6 family
                - p6-b200.48xlarge
                - p6e-gb200.36xlarge
                # G6 family
                - g6.xlarge
                - g6.2xlarge
                - g6.4xlarge
                - g6.8xlarge
                - g6.12xlarge
                - g6.16xlarge
                - g6.24xlarge
                - g6.48xlarge
                # G6e family
                - g6e.xlarge
                - g6e.2xlarge
                - g6e.4xlarge
                - g6e.8xlarge
                - g6e.12xlarge
                - g6e.16xlarge
                - g6e.24xlarge
                - g6e.48xlarge
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
    EOT
  ]
}
##########################################################################
# Kubeai
# Debug:
#     helm upgrade --install kubeai-models -n kubeai kubeai/models -f kubernetes/kubeai/models/models-override-values.yaml
##########################################################################
locals {
  kubeai_version    = "0.19.0"
  kubeai_namespace  = "kubeai"
  kubeai_repository = "https://www.kubeai.org"
}

resource "helm_release" "kubeai" {
  name             = "kubeai"
  chart            = "kubeai"
  repository       = local.kubeai_repository
  version          = local.kubeai_version
  namespace        = local.kubeai_namespace
  create_namespace = true
  replace          = true
  wait             = false
  values           = [templatefile("${path.module}/kubernetes/kubeai/kubeai/kubeai-override-values.yaml", {})]
}

resource "helm_release" "kubeai_models" {
  name       = "kubeai-models"
  chart      = "models"
  repository = local.kubeai_repository
  version    = local.kubeai_version
  namespace  = local.kubeai_namespace
  wait       = false
  values     = [templatefile("${path.module}/kubernetes/kubeai/models/models-override-values.yaml", {})]
  depends_on = [helm_release.kubeai]
}
