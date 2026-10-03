#!/usr/bin/env bash
# Creates the 5 key pairs referenced in terraform.tfvars. Keep the .pem files safe (they are git-ignored).
set -euo pipefail
for k in key-web1 key-web2 key-app key-batch key-db; do
  aws ec2 create-key-pair --profile account_a --region ap-south-1 \
    --key-name "$k" --query KeyMaterial --output text > "$k.pem"
  chmod 400 "$k.pem"
done
