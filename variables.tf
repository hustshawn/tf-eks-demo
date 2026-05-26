
variable "aws_profile" {
  type        = string
  default     = "default"
  description = "The AWS CLI profile to use"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.6.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "region" {
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy the resources"
}

variable "cluster_name" {
  type        = string
  default     = "tf-eks-demo"
  description = "The name of the EKS cluster"
}

variable "cluster_version" {
  type        = string
  default     = "1.35"
  description = "The Kubernetes version for the EKS cluster"
}

variable "dns_domain" {
  type        = string
  default     = "example.com"
  description = "The domain for the application"
}

variable "slack_api_url" {
  type        = string
  default     = "https://hooks.slack.com/services/xxxxxxx"
  description = "The Slack API URL used for the Prometheus Alertmanager"
}

variable "enable_nvidia_device_plugin" {
  type        = bool
  default     = false
  description = "Whether to enable the NVIDIA Device Plugin"
}

variable "enable_aws_efa_device_plugin" {
  type        = bool
  default     = false
  description = "Whether to enable the AWS EFA Device Plugin"
}

variable "enable_capacity_reservation" {
  type        = bool
  default     = false
  description = "Whether to provision resources tied to an EC2 On-Demand Capacity Reservation (ODCR)"
}

variable "capacity_reservation_id" {
  type        = string
  default     = null
  description = "The ID of the capacity reservation. Required when enable_capacity_reservation is true."
}

variable "idc_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region where the IAM Identity Center instance lives (often differs from the cluster region)."
}

variable "argocd_admin_sso_group_name" {
  type        = string
  description = "Display name of the IAM Identity Center group mapped to the ArgoCD ADMIN role."
}
