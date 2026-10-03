# AWS / Terraform Assessment

Terraform for five tasks: multi-instance EC2, remote state with locking, multi-account IAM,
a least-privilege CI policy, and a cross-account trust bug fix.
Written explanations and design decisions are in [`NOTES.md`](NOTES.md).

> Status: written but **not applied or validated** against AWS. Run `terraform fmt -recursive` and
> `terraform validate` in each folder first. The account IDs (`000000000000`, `111111111111`) and other
> names are placeholders.

## Repository layout

```
aws-assessment/
├── README.md
├── NOTES.md                    # answers + explanations for every task
├── task1-ec2/                  # Task 1 (+ backend from Task 2)
│   ├── backend.tf              # S3 + DynamoDB backend
│   ├── main.tf  variables.tf  outputs.tf  terraform.tfvars
│   ├── create-keypairs.sh      # creates the 5 key pairs
│   └── modules/ec2-fleet/      # the reusable module
├── task2-remote-state/         # Task 2: S3 bucket + DynamoDB lock table
│   ├── main.tf
│   └── README.md
├── task3-iam/
│   ├── account-a/main.tf       # groups, users, roleA, roleB
│   └── account-b/main.tf       # roleC
├── task4-ci-policy/
│   ├── ci-policy.json          # custom least-privilege policy
│   └── attach.tf               # attaches it to the `ci` user
└── task5-fix/
    ├── broken.tf.txt           # original snippet
    └── main.tf                 # fixed version
```

## Prerequisites
- Terraform >= 1.5 and AWS CLI v2
- Two AWS accounts (a sandbox, plus a second via AWS Organizations) for a real apply, with CLI profiles:
  ```bash
  aws configure --profile account_a
  aws configure --profile account_b
  ```
- Without real accounts you can still run `init`, `validate` and `plan` (the plan needs credentials for the AMI lookup).

## Before you apply, replace the placeholders
| What | Where |
|---|---|
| Subnet ID | `task1-ec2/terraform.tfvars` |
| Unique state bucket name | `task2-remote-state` (`-var state_bucket_name=...`) and `task1-ec2/backend.tf` |
| Account IDs | `task3-iam/*/main.tf` variables, `task4-ci-policy/ci-policy.json` |
| Shared S3 bucket name | `task3-iam/account-b/main.tf` (`bucket_name`) |
| ECR repo, ECS cluster/service, task roles, artifacts bucket | `task4-ci-policy/ci-policy.json` |

## Run order

### 1. Task 2: remote state (first, because Task 1 depends on it)
```bash
cd task2-remote-state
terraform init
terraform apply -var state_bucket_name=<globally-unique-name>
```

### 2. Task 1: EC2 fleet
```bash
cd task1-ec2
./create-keypairs.sh                  # key-web1, key-web2, key-app, key-batch, key-db
# edit backend.tf (bucket name) and terraform.tfvars (subnet)
terraform init -migrate-state
terraform plan
terraform apply
terraform output                      # instance_ids and instance_private_ips maps
```

### 3. Task 3: IAM (Account A first, then Account B)
```bash
cd task3-iam/account-a && terraform init && terraform apply
cd ../account-b        && terraform init && terraform apply
```
roleB must exist before roleC's trust policy can reference it. Create access keys for `engine` and `ci`
out-of-band (`aws iam create-access-key --user-name ci`); they are intentionally not in Terraform state.

### 4. Task 4: CI policy
```bash
cd task4-ci-policy && terraform init && terraform apply
```
Run after Task 3, since it attaches the policy to the `ci` user.

### 5. Task 5: bug fix
`task5-fix/main.tf` is the corrected code. It is the same as `task3-iam/account-b/main.tf`.
Do not apply both against the same account.

## Task summary
| Task | What it delivers | Key point |
|---|---|---|
| 1 | Module creating 5 EC2 instances from one `instances` map | `db` is protected with `prevent_destroy` + `disable_api_termination`; io1/io2 used; outputs are name→ID and name→private IP |
| 2 | S3 bucket + DynamoDB lock table, backend wired into Task 1 | Locking stops concurrent applies; local state does not |
| 3 | group1, group2, roleA, roleB (Account A); roleC (Account B) | roleC trusts only roleB's exact ARN |
| 4 | Custom policy for `ci` | ECR push, ECS deploy, S3 read-only, PassRole scoped |
| 5 | Fixed trust policy and role reference | `user/roleB` → `role/roleB`, invalid HCL line, bucket scoping |

## Cleanup
```bash
cd task1-ec2 && terraform destroy   # blocked on purpose by the protected `db` instance
```
To destroy everything, first set `protected = false` for `db` (or remove its `prevent_destroy` / termination
protection), then destroy in reverse order: task4, task3 (B then A), task1, and finally task2
(the state bucket has `prevent_destroy` and versioned objects; empty it manually).

## Cost note
The default instance types (e.g. r5.large, c5.large) and the io1/io2 volumes cost real money.
Shrink the types for a sandbox and destroy when finished.
