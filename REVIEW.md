# Terraform Code Review

## Priority Overview

| Priority | # | File | Topic | Status |
| -------- | - | ---- | ----- | ------ |
| 🔴 High | 1 | `main.tf` | Missing AWS profile on providers | ✅ Done |
| 🔴 High | 9 | `main.tf:38-54` | Static token on kubernetes/kubectl providers (expiry risk) | ✅ Done |
| 🔴 High | 6 | `variables.tf:50-53` | `capacity_reservation_id` always required, breaks others | ⬜ Open |
| 🟡 Medium | 2 | `variables.tf` / `main.tf` | `cluster_name` variable unused | ✅ Done |
| 🟡 Medium | 8 | `karpenter.tf:181-224` | GPU NodePool missing `nvidia.com/gpu` resource limit | ⬜ Open |
| 🟡 Medium | 5 | `efs.tf:51` | EFS StorageClass `directoryPerms = "777"` too permissive | ✅ Done |
| 🔵 Low | 4 | `karpenter.tf:22-24` | IRSA vs Pod Identity inconsistency for Karpenter | ⬜ Deferred |
| 🔵 Low | 7 | `addons.tf:60-61` | Confusing dead comment on `enable_aws_efs_csi_driver` | ✅ Done |
| 🔵 Low | 10 | `karpenter.tf` | Large inline YAML — consider `templatefile()` | ⬜ Open |
| 🔵 Low | 11 | `efs.tf:66-128` | Large dead-code block (commented-out StorageClass + PV/PVC) | ✅ Done |
| ~~N/A~~ | ~~3~~ | ~~`addons.tf:178-179`~~ | ~~Overly broad S3 IAM (wildcard bucket ARNs)~~ | ~~Ignored~~ |

---

## 🔴 High Priority

### ✅ #1 — Missing AWS profile on providers (`main.tf`)

**Problem:** Both `aws` providers had no `profile`, defaulting to the shell's `AWS_DEFAULT_PROFILE`.

**Fix:** Added `aws_profile` variable (default `"default"`) wired into both providers. `dev.auto.tfvars` overrides to `"main"`.

```hcl
# variables.tf
variable "aws_profile" {
  type    = string
  default = "default"
}

# main.tf
provider "aws" {
  region  = local.region
  profile = var.aws_profile
}
```

> Note: The S3 backend does not accept variables — pass via `AWS_PROFILE=main terraform plan`.

---

### ⬜ #9 — Static token on kubernetes/kubectl providers (`main.tf:38-54`)

**Problem:** `data.aws_eks_cluster_auth.this.token` is fetched once at plan time with a short TTL (~15 min). On long `apply` runs the token may expire mid-apply causing unexpected failures.

**Fix:** Uncomment the existing `exec` block already present at `main.tf:43-46` and apply the same pattern to the `kubectl` provider. The `helm` provider already does this correctly.

```hcl
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", local.region]
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", local.region]
  }
}
```

---

### ⬜ #6 — `capacity_reservation_id` always required (`variables.tf:50-53`)

**Problem:** The variable has no default. Anyone running without `dev.auto.tfvars` gets an immediate error even if they don't use reserved capacity — because the reserved-capacity resources are unconditionally created.

**Fix:** Add default `""` and guard both reserved-capacity resources with `count`:

```hcl
# variables.tf
variable "capacity_reservation_id" {
  type    = string
  default = ""
}

# karpenter.tf
resource "kubectl_manifest" "karpenter_reserved_capacity_node_class" {
  count      = var.capacity_reservation_id != "" ? 1 : 0
  depends_on = [helm_release.karpenter]
  ...
}

resource "kubectl_manifest" "karpenter_reserved_capacity_node_pool" {
  count      = var.capacity_reservation_id != "" ? 1 : 0
  depends_on = [helm_release.karpenter, kubectl_manifest.karpenter_reserved_capacity_node_class]
  ...
}
```

---

## 🟡 Medium Priority

### ✅ #2 — `cluster_name` variable unused (`variables.tf`, `main.tf`)

**Problem:** `var.cluster_name` was declared but `local.name` was hardcoded to `"tf-eks-demo"`.

**Fix:** `local.name = var.cluster_name`. Default is still `"tf-eks-demo"` — no breaking change.

---

### ⬜ #8 — GPU NodePool missing `nvidia.com/gpu` resource limit (`karpenter.tf:181-224`)

**Problem:** `gpu-nodepool` only sets `limits.cpu: 5000` with no GPU resource limit. Karpenter could scale GPU nodes unboundedly.

**Fix:** Add a GPU limit to the NodePool spec:

```yaml
limits:
  cpu: 5000
  nvidia.com/gpu: "64"   # adjust to your capacity budget
```

---

### ⬜ #5 — EFS StorageClass `directoryPerms = "777"` (`efs.tf:51`)

**Problem:** World-writable permissions on EFS access point directories is overly permissive for shared model cache storage.

**Fix:** Use `"755"` (owner write, group/world read+exec) or `"750"` if only the owning UID needs access:

```hcl
parameters = {
  provisioningMode = "efs-ap"
  fileSystemId     = module.efs.id
  directoryPerms   = "755"
}
```

---

## 🔵 Low Priority

### ⬜ #4 — IRSA vs Pod Identity inconsistency for Karpenter (`karpenter.tf:22-24`) — Deferred

Karpenter uses IRSA (`enable_irsa = true`) while all other add-ons use Pod Identity. Works fine, low priority until a full IRSA-to-Pod-Identity migration is warranted.

---

### ⬜ #7 — Dead comment on `enable_aws_efs_csi_driver` (`addons.tf:60-61`)

The commented-out `# enable_aws_efs_csi_driver = true` above the `false` is misleading — enabling it would conflict with the native EKS addon already managing EFS CSI. Delete the comment line.

---

### ⬜ #10 — Large inline YAML in Karpenter resources (`karpenter.tf`)

NodeClass and NodePool definitions are large heredoc YAML blocks inline in Terraform. Moving them to `karpenter-resources/*.yaml` with `templatefile()` would improve readability and diff quality. Cosmetic only.

---

### ⬜ #11 — Dead code in `efs.tf` (`efs.tf:66-128`)

Large commented-out block covering a duplicate `StorageClass` and unused PV/PVC resources (leftover from Dify). Safe to delete.
