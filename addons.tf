module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0" #ensure to update this to the latest/desired version

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn
  # disable the Telemetry from AWS using CloudFormation
  observability_tag = null

  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
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
  }

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    chart_version = "1.9.2"
    set = [
      {
        name  = "vpcId" # explicitly set the vpcId, otherwise it may not able to retrieve the vpcId from the node
        value = module.vpc.vpc_id
      },
    ]
  }

  enable_metrics_server        = true
  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    values = [
      templatefile("${path.module}/kubernetes/kube-prometheus-stack/values.override.yaml", {
        ingressClassName = "alb"
        grafana_host     = local.grafana_host
        acm_cert_arn     = data.aws_acm_certificate.issued.arn
        slack_api_url = var.slack_api_url
      })
    ]
  }

  enable_external_dns            = true
  external_dns_route53_zone_arns = [data.aws_route53_zone.selected.arn] # need the zone arns to create role
  enable_cert_manager            = true
  # cert_manager_route53_hosted_zone_arns  = ["arn:aws:route53:::hostedzone/XXXXXXXXXXXXX"]

  enable_ingress_nginx = true
  ingress_nginx = {
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
    #   chart_version    = "0.14.0"
    #   repository       = "https://nvidia.github.io/k8s-device-plugin"
    #   values           = [file("${path.module}/kubernetes/nvidia-device-plugin/values.yaml")]
    # }
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

  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "Environment" = "dev"
  })
}



module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-ebs-csi-driver-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}
