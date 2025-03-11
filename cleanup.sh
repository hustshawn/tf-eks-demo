STACK_NAME="tf-eks-demo"
# Delete the LoadBalancer type service from Nginx ingress controller
echo "Destroying LoadBalancer type service from Nginx ingress controller..."

# Delete the Ingress/SVC before removing the addons
TMPFILE=$(mktemp)
terraform output -raw configure_kubectl > "$TMPFILE"
# check if TMPFILE contains the string "No outputs found"
if [[ ! $(cat $TMPFILE) == *"No outputs found"* ]]; then
  echo "No outputs found, skipping kubectl delete"
  source "$TMPFILE"
  kubectl delete svc -n ingress-nginx ingress-nginx-controller
fi

# Delete the Ingress from all namespaces
kubectl delete ingress --all --all-namespaces

# Delete the Karpenter node pools so that trigger the deletion of the nodes
kubectl delete nodepool --all

# List of Terraform modules to apply in sequence
targets=(
  "module.eks_blueprints_addons"
  "module.eks"
)

# Destroy modules in sequence
for target in "${targets[@]}"
do
  echo "Destroying module $target..."
  destroy_output=$(terraform destroy -target="$target" -auto-approve 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete"* ]]; then
    echo "SUCCESS: Terraform destroy of $target completed successfully"
  else
    echo "FAILED: Terraform destroy of $target failed"
    exit 1
  fi
done

echo "Destroying Security Groups..."
for sg in $(aws ec2 describe-security-groups \
  --filters "Name=tag:elbv2.k8s.aws/cluster,Values=${STACK_NAME}" \
  --query 'SecurityGroups[].GroupId' --output text); do \
    aws ec2 delete-security-group --group-id "$sg"; \
  done

# Destroy everything else
echo "Destroying everything else..."
terraform destroy -auto-approve
