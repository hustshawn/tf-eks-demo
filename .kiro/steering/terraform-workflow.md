# Terraform Workflow Standards

## Terraform Plan and Apply Commands

**CRITICAL REQUIREMENT**: When running terraform plan commands, ALWAYS use a static output file named "planfile".

### Required Command Format:
- **Plan**: `terraform plan -out=planfile`
- **Apply**: `terraform apply planfile`

### Never Use:
- `terraform plan` (without output file)
- `terraform apply` (without planfile)
- `terraform apply -auto-approve`

### Rationale:
- Ensures consistency between plan and apply operations
- Provides audit trail of planned changes
- Prevents accidental application of unreviewed changes
- Follows infrastructure-as-code best practices

### Example Workflow:
```bash
# Always use this pattern
terraform plan -out=planfile
terraform apply planfile

# For validation
terraform validate
terraform fmt -check
```

This rule applies to all terraform operations in this EKS infrastructure project.