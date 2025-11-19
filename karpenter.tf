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
  chart   = "karpenter"
  version = "1.6.1"
  wait    = false

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
    controller:
      resources:
        limits:
          cpu: 1
          memory: 1Gi
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

  yaml_body = <<-YAML
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
          operator: Gt
          values: [ "4" ]
        - key: "karpenter.k8s.aws/instance-hypervisor"
          operator: In
          values: [ "nitro" ]
        - key: "karpenter.k8s.aws/instance-generation"
          operator: Gt
          values: [ "2" ]
    limits:
      cpu: 1000
    disruption:
      consolidationPolicy: WhenEmptyOrUnderutilized
      consolidateAfter: 300s
  YAML
}

resource "kubectl_manifest" "karpenter_gpu_node_class" {
  depends_on = [helm_release.karpenter]

  yaml_body = <<-YAML
  apiVersion: karpenter.k8s.aws/v1
  kind: EC2NodeClass
  metadata:
    name: gpu
  spec:
    amiFamily: AL2023
    amiSelectorTerms:
    - alias: al2023@latest
    instanceStorePolicy: RAID0
    blockDeviceMappings:
      - deviceName: /dev/xvda
        ebs:
          volumeSize: 500Gi
          volumeType: gp3
          encrypted: true
    metadataOptions:
      httpEndpoint: enabled
      httpProtocolIPv6: disabled
      httpPutResponseHopLimit: 1
      httpTokens: required
    role: ${module.eks.cluster_name}
    securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
    subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
    tags:
      karpenter.sh/discovery: ${module.eks.cluster_name}
  YAML
}

resource "kubectl_manifest" "karpenter_gpu_node_pool" {
  depends_on = [
    helm_release.karpenter,
    kubectl_manifest.karpenter_gpu_node_class
  ]
  yaml_body = <<-YAML
  apiVersion: karpenter.sh/v1
  kind: NodePool
  metadata:
    name: gpu-nodepool
  spec:
    disruption:
      budgets:
      - nodes: 10%
      consolidateAfter: 300s
      consolidationPolicy: WhenEmpty
    limits:
      cpu: 5000
    template:
      metadata:
        labels:
          owner: data-engineer
          vpc.amazonaws.com/efa.present: "true"
      spec:
        expireAfter: 720h
        nodeClassRef:
          group: karpenter.k8s.aws
          kind: EC2NodeClass
          name: gpu
        taints:
          - key: nvidia.com/gpu
            value: "true"
            effect: "NoSchedule"
        requirements:
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["g6", "g6e", "p4", "p4d", "p4de", "p5", "p5en", "p6-b200" ]
          - key: "kubernetes.io/arch"
            operator: In
            values: [ "amd64" ]
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: [ "spot", "on-demand" ]
    limits:
      cpu: 5000
  YAML
}

# FlowSchema
resource "kubectl_manifest" "karpenter_controller_flow_schema" {
  yaml_body = <<-YAML
  apiVersion: flowcontrol.apiserver.k8s.io/v1
  kind: FlowSchema
  metadata:
    name: karpenter-workload
  spec:
    distinguisherMethod:
      type: ByUser
    matchingPrecedence: 1000
    priorityLevelConfiguration:
      name: workload-high
    rules:
    - nonResourceRules:
      - nonResourceURLs:
        - '*'
        verbs:
        - '*'
      resourceRules:
      - apiGroups:
        - '*'
        clusterScope: true
        namespaces:
        - '*'
        resources:
        - '*'
        verbs:
        - '*'
      subjects:
      - kind: ServiceAccount
        serviceAccount:
          name: karpenter
          namespace: "${helm_release.karpenter.namespace}"
  YAML
}

resource "kubectl_manifest" "karpenter_leader_election_flow_schema" {
  yaml_body = <<-YAML
  apiVersion: flowcontrol.apiserver.k8s.io/v1
  kind: FlowSchema
  metadata:
    name: karpenter-leader-election
  spec:
    distinguisherMethod:
      type: ByUser
    matchingPrecedence: 200
    priorityLevelConfiguration:
      name: leader-election
    rules:
    - resourceRules:
      - apiGroups:
        - coordination.k8s.io
        namespaces:
        - '*'
        resources:
        - leases
        verbs:
        - get
        - create
        - update
      subjects:
      - kind: ServiceAccount
        serviceAccount:
          name: karpenter
          namespace: "${helm_release.karpenter.namespace}"
  YAML
}

################################################################################
# Reserved Capacity NodeClass & NodePool
################################################################################

resource "kubectl_manifest" "karpenter_reserved_capacity_node_class" {
  depends_on = [helm_release.karpenter]

  yaml_body = <<-YAML
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: reserved-capacity
spec:
  amiFamily: AL2023
  amiSelectorTerms:
  - alias: al2023@latest
  instanceStorePolicy: RAID0
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 800Gi
        volumeType: gp3
        iops: 3000
        throughput: 150
        encrypted: true
        deleteOnTermination: true
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 1
    httpTokens: required
  role: ${module.eks.cluster_name}
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${module.eks.cluster_name}
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${module.eks.cluster_name}
  capacityReservationSelectorTerms:
  - id: ${var.capacity_reservation_id}
  tags:
    karpenter.sh/discovery: ${module.eks.cluster_name}
YAML
}

resource "kubectl_manifest" "karpenter_reserved_capacity_node_pool" {
  depends_on = [
    helm_release.karpenter,
    kubectl_manifest.karpenter_reserved_capacity_node_class
  ]

  yaml_body = <<-YAML
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: reserved-capacity-pool
spec:
  weight: 10
  template:
    metadata:
      labels:
        vpc.amazonaws.com/efa.present: "true"
        nvidia.com/gpu.present: "true"
    spec:
      expireAfter: 720h
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: reserved-capacity
      taints:
        - key: nvidia.com/gpu
          value: "true"
          effect: "NoSchedule"
      requirements:
      - key: "karpenter.sh/capacity-type"
        operator: In
        values: ["reserved", "on-demand"]
      - key: "karpenter.k8s.aws/instance-family"
        operator: In
        values: ["p4", "p4d", "p4de", "p5", "p5en", "p6-b200"]
      - key: "kubernetes.io/arch"
        operator: In
        values: ["amd64"]
      - key: "karpenter.k8s.aws/instance-hypervisor"
        operator: In
        values: ["nitro"]
  limits:
    cpu: 5000
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 300s
YAML
}


