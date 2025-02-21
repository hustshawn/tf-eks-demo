locals {
  namespace = "karpenter"
}

################################################################################
# Controller & Node IAM roles, SQS Queue, Eventbridge Rules
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.24"

  cluster_name          = module.eks.cluster_name
  enable_v1_permissions = true
  namespace             = local.namespace

  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = local.name

  # EKS Fargate does not support pod identity
  create_pod_identity_association = false
  enable_irsa                     = true
  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn

  tags = local.tags
}

################################################################################
# Helm charts
################################################################################

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = local.namespace
  create_namespace = true
  repository       = "oci://public.ecr.aws/karpenter"
  # To avoid 403 error from public ECR
  # ref: https://github.com/aws/karpenter-provider-aws/issues/6357
  # repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  # repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "1.1.3"
  wait                = false

  values = [
    <<-EOT
    dnsPolicy: Default
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter.iam_role_arn}
    webhook:
      enabled: false
    EOT
  ]

  lifecycle {
    ignore_changes = [
      repository_password
    ]
  }
}

################################################################################
# Karpenter Node Class & Node Pool
################################################################################

resource "kubectl_manifest" "karpenter_node_class" {
  depends_on = [helm_release.karpenter]
  yaml_body  = <<-YAML
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
  - alias: al2023@latest
  role: ${module.eks.cluster_name}
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${module.eks.cluster_name}
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${module.eks.cluster_name}
  tags:
    karpenter.sh/discovery: ${module.eks.cluster_name}
YAML
}

resource "kubectl_manifest" "karpenter_node_pool" {
  depends_on = [
    helm_release.karpenter,
    kubectl_manifest.karpenter_node_class
  ]
  yaml_body = <<-YAML
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
      - key: "karpenter.k8s.aws/instance-category"
        operator: In
        values: [ "c", "m", "r" ]
      - key: "karpenter.k8s.aws/instance-cpu"
        operator: In
        values: [ "4", "8", "16", "32" ]
      - key: "karpenter.k8s.aws/instance-hypervisor"
        operator: In
        values: [ "nitro" ]
      - key: "karpenter.k8s.aws/instance-generation"
        operator: Gt
        values: [ "2" ]
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
YAML
}
