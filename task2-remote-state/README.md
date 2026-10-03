# Task 2: Remote state and locking

## What is in this task
| Piece | Location |
|---|---|
| S3 bucket (versioned, encrypted, private) + DynamoDB lock table | `main.tf` (this folder) |
| Backend block that makes Task 1 use them | `../task1-ec2/backend.tf` |
| Explanation (local state vs. backend) | this file, and `../NOTES.md` |

`backend.tf` has to sit inside `task1-ec2/` because Terraform only reads backend config from the
directory it runs in. It is the same block shown below.

## Steps
```bash
# 1. Create bucket + lock table (local state, applied once)
cd task2-remote-state
terraform init
terraform apply -var state_bucket_name=<globally-unique-name>

# 2. Put that bucket name into ../task1-ec2/backend.tf, then migrate Task 1 to it
cd ../task1-ec2
terraform init -migrate-state
```

## The backend block (../task1-ec2/backend.tf)
```hcl
terraform {
  backend "s3" {
    bucket         = "<your-state-bucket>"
    key            = "task1-ec2/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
    profile        = "account_a"
  }
}
```
Backend blocks cannot use variables, so the values are literal.

## What happens today (local state) if two people run `apply` at the same time
Each person has their own `terraform.tfstate` on their own machine. Terraform's local lock only covers
one machine, so it does not stop two people. Both plans start from a stale or empty state, so both
applies can succeed. The result is duplicate instances, and whoever finishes last overwrites a state
file the other never saw, which leaves orphaned resources that Terraform no longer tracks.

## How the backend prevents it
There is one shared state in S3. Before any state-writing operation, Terraform does a conditional write
of a `LockID` item to the DynamoDB table. The second person's run fails with "Error acquiring the state
lock" (showing who holds it) and has to wait. Versioning on the bucket lets you recover from a bad state.

Note: Terraform 1.10+ supports S3-native locking (`use_lockfile = true`) and the DynamoDB option is
being deprecated. DynamoDB is used here because the task asks for it.
