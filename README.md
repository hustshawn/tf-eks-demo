# Terraform EKS Demo

This repository demonstrates Terraform configurations for deploying a production-ready Amazon EKS cluster with essential add-ons and monitoring capabilities.

## Features

- EKS cluster (v1.30) with managed node groups
- Karpenter for auto-scaling
- Monitoring stack:
  - Prometheus
  - Grafana
  - AlertManager
- Essential add-ons:
  - AWS Load Balancer Controller
  - External DNS
  - Cert Manager
  - AWS EBS CSI Driver
  - Metrics Server
  - Ingress NGINX
  - ArgoCD

## Prerequisites

- Terraform >= 1.3
- AWS CLI configured with appropriate credentials
- kubectl

## Quick Start

1. Clone this repository

2. Initialize Terraform:
   ```bash
   terraform init
   ```

3. Review and apply the Terraform configuration:
   ```bash
   terraform plan -out planfile
   terraform apply planfile
   ```

4. Configure kubectl to connect to your cluster (the command will be provided in the Terraform output):
   ```bash
   aws eks --region <region> update-kubeconfig --name <cluster-name>
   ```

## Security

- OIDC provider enabled for IAM roles for service accounts
- Security groups automatically managed
- Pod security standards enforced
- Secure communication with private endpoints

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
