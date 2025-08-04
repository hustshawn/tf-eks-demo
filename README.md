# Terraform EKS Demo

This repository demonstrates Terraform configurations for deploying a production-ready Amazon EKS cluster with essential add-ons, GPU support, and advanced scaling capabilities using Karpenter.

## Features

### Core Infrastructure
- **EKS cluster (v1.33)** with Fargate profiles for system components
- **Karpenter v1.6.1** for intelligent auto-scaling and cost optimization
- **Reserved Capacity Support** - Native ODCR integration for cost-effective GPU workloads
- **GPU Workload Ready** - Optimized for ML/AI with NVIDIA device plugin and EFA support

### Scaling & Compute
- **Multiple NodePools**:
  - `default` - General purpose workloads (c/m/r instances)
  - `gpu-nodepool` - GPU workloads (g6/p4/p5 instances) 
  - `reserved-capacity-pool` - Reserved capacity with GPU optimization
- **Advanced Features**:
  - RAID0 instance store for performance
  - Custom EBS configurations (800Gi gp3 volumes)
  - EFA networking for high-performance computing

### Monitoring & Observability
- **Prometheus Stack**:
  - Prometheus
  - Grafana
  - AlertManager
- **AWS CloudWatch Observability** addon
- **Metrics Server** for HPA/VPA

### Essential Add-ons
- AWS Load Balancer Controller
- External DNS with Route53 integration
- Cert Manager for TLS automation
- AWS EBS CSI Driver
- AWS EFS CSI Driver
- Ingress NGINX
- ArgoCD for GitOps

## Prerequisites

- Terraform >= 1.3
- AWS CLI configured with appropriate credentials
- kubectl
- (Optional) AWS Capacity Reservation for cost optimization

## Configuration

### Required Variables

Create a `dev.auto.tfvars` file with the following variables:

```hcl
region                       = "us-west-2"
dns_domain                   = "your-domain.com"
enable_nvidia_device_plugin  = true
enable_aws_efa_device_plugin = true
capacity_reservation_id      = "cr-xxxxxxxxxxxxxxxxx"  # Optional: Your capacity reservation ID
```

### Key Configuration Files

- `eks.tf` - EKS cluster configuration
- `karpenter.tf` - Karpenter controller and NodePool definitions
- `addons.tf` - EKS add-ons and Helm charts
- `vpc.tf` - VPC and networking setup

## Quick Start

1. Clone this repository

2. Create your configuration file:
   ```bash
   cp dev.auto.tfvars.example dev.auto.tfvars
   # Edit dev.auto.tfvars with your values
   ```

3. Initialize Terraform:
   ```bash
   terraform init
   ```

4. Review and apply the Terraform configuration:
   ```bash
   terraform plan -out=planfile
   terraform apply planfile
   ```

5. Configure kubectl to connect to your cluster:
   ```bash
   aws eks --region us-west-2 update-kubeconfig --name tf-eks-demo --alias tf-eks-demo
   ```

## Reserved Capacity Setup

This cluster supports AWS On-Demand Capacity Reservations (ODCRs) for cost optimization:

### Features
- **Native ODCR Support** - Karpenter v1.6.1 with ReservedCapacity feature gate enabled
- **Capacity Prioritization** - Reserved capacity first, on-demand fallback
- **GPU Optimized** - Configured for P4/P5 instances with EFA networking

### Usage
1. Create a capacity reservation in AWS EC2 console
2. Update `capacity_reservation_id` in your `dev.auto.tfvars`
3. Deploy GPU workloads with appropriate tolerations:

```yaml
apiVersion: v1
kind: Pod
spec:
  tolerations:
  - key: nvidia.com/gpu
    operator: Equal
    value: "true"
    effect: NoSchedule
  nodeSelector:
    karpenter.sh/capacity-type: reserved  # Optional: Force reserved capacity
```

## NodePool Configuration

### Available NodePools

1. **default** - General purpose workloads
   - Instance types: c/m/r families
   - Capacity types: spot, on-demand

2. **gpu-nodepool** - GPU workloads  
   - Instance types: g6, g6e, p4, p4d, p5, p5en
   - Features: EFA support, NVIDIA taints

3. **reserved-capacity-pool** - Reserved capacity
   - Instance types: p4, p4d, p5, p5en
   - Capacity types: reserved (priority), on-demand (fallback)
   - Features: 800Gi EBS, RAID0 instance store, EFA support

## Monitoring & Access

### Accessing Services

After deployment, you can access the following services:

- **ArgoCD**: `https://argocd.your-domain.com`
- **Grafana**: `https://grafana.your-domain.com`
- **Prometheus**: `https://prometheus.your-domain.com`

### Useful Commands

```bash
# Check Karpenter status
kubectl get nodepools
kubectl get ec2nodeclasses

# Monitor node provisioning
kubectl logs -f -n karpenter -l app.kubernetes.io/name=karpenter

# Check GPU nodes
kubectl get nodes -l nvidia.com/gpu.present=true

# View capacity reservations status
kubectl describe ec2nodeclass reserved-capacity
```

## Troubleshooting

### Common Issues

1. **Capacity Reservation Not Found**
   ```bash
   # Check if capacity reservation exists and is in correct region
   aws ec2 describe-capacity-reservations --capacity-reservation-ids cr-xxxxxxxxxxxxxxxxx
   ```

2. **GPU Workloads Not Scheduling**
   ```bash
   # Ensure tolerations are set correctly
   kubectl describe pod <pod-name>
   
   # Check NodePool status
   kubectl get nodepool gpu-nodepool -o yaml
   ```

3. **Karpenter Not Scaling**
   ```bash
   # Check Karpenter logs
   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100
   
   # Verify NodePool configuration
   kubectl get nodepools -o wide
   ```

## Cost Optimization

### Reserved Capacity Benefits
- **Cost Savings**: Up to 75% savings compared to on-demand pricing
- **Capacity Assurance**: Guaranteed capacity availability
- **Flexible Usage**: Can be used across multiple workloads

### Best Practices
- Use reserved capacity for predictable GPU workloads
- Configure appropriate instance families in NodePools
- Monitor utilization with CloudWatch metrics
- Set appropriate node expiration times (720h default)

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
