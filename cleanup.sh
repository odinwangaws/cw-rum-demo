#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-cw-rum-demo}"
REGION="${AWS_REGION:-us-east-1}"

echo "=== CloudWatch RUM Demo Cleanup ==="
echo "Deleting stack: $STACK_NAME (region: $REGION)"
echo ""

aws cloudformation delete-stack \
  --stack-name "$STACK_NAME" \
  --region "$REGION"

echo "Waiting for stack deletion..."
aws cloudformation wait stack-delete-complete \
  --stack-name "$STACK_NAME" \
  --region "$REGION"

echo "Done. All resources removed."
