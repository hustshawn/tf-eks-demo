
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
