# NOTES

Placeholders to replace before applying: `subnet-...` (task1 tfvars), state bucket name
(`task2-remote-state` + `task1-ec2/backend.tf`), account IDs `000000000000` / `111111111111`,
bucket names, ECR/ECS names in `ci-policy.json`. Terraform and AWS profiles `account_a` / `account_b` are needed.
Nothing was executed against AWS; run `terraform fmt -recursive && terraform validate` in each folder first.

## Layout and run order
1. `task1-ec2/` needs the Task 2 stack first, so start with `task2-remote-state/`: `terraform init && terraform apply -var state_bucket_name=<unique>` (local state, once).
2. `task1-ec2/`: run `./create-keypairs.sh`, set `backend.tf` + `terraform.tfvars`, then `terraform init -migrate-state`, `plan`, `apply`.
3. `task3-iam/account-a/` first (roleB must exist), then `task3-iam/account-b/`.
4. `task4-ci-policy/`: attaches `ci-policy.json` to the `ci` user (after step 3).
5. `task5-fix/`: corrected code (`broken.tf.txt` is the original).

---

## Task 1: Multi-instance EC2
- One variable, `instances` (map of name => settings), drives everything. All five differ in instance type, root volume type (gp3, gp2, io1, standard, io2), size and key pair. `db` and `app` use provisioned IOPS (io2 / io1).
- Tags `Name`, `Environment`, `Owner` are applied on every instance.
- `st1`/`sc1` cannot be root volumes, so the magnetic option used is `standard`. A validation block rejects invalid root types and io1/io2 without `iops`.
- Terraform's `prevent_destroy` must be a literal and cannot vary per `for_each` item. So the module splits the single variable into `standard` and `protected` sets (by the `protected` flag) and uses two resource blocks. There are still no hardcoded per-instance resources.

### Which instance is protected, and why
**`db`**. It is the only stateful instance (io2 volume, database workload). Destroying or replacing it loses data and means a slow rebuild. The web, app and batch hosts are stateless and can be recreated from code.
`prevent_destroy = true` makes Terraform error on any plan that would destroy or replace it. It only guards Terraform, so I also set `disable_api_termination = true`, which blocks termination from the console and CLI. To deliberately remove `db`: flip `protected` / remove the lifecycle block and disable termination protection first.

## Task 2: Remote state and locking
Backend: S3 bucket (versioned, encrypted, public access blocked) plus DynamoDB table `terraform-locks` (hash key `LockID`), created in `task2-remote-state/` and wired in via `task1-ec2/backend.tf` (it must live in the Task 1 folder to take effect). See also `task2-remote-state/README.md`.

**Today, with local state:** each person has their own `terraform.tfstate` on their own machine. Terraform's local lock only covers one machine, so it does not stop two people. Both plans start from a stale or empty state, so both applies can succeed. The result is duplicate instances, and whoever finishes last overwrites a state file the other never saw, which leaves orphaned resources that Terraform no longer tracks.

**With the S3 + DynamoDB backend:** there is one shared state. Before any state-writing operation, Terraform does a conditional write of a `LockID` item to DynamoDB. The second person's run fails with "Error acquiring the state lock" (showing who holds it) and must wait. Versioning on the bucket allows recovery from a bad state.
Note: Terraform 1.10+ supports S3-native locking (`use_lockfile = true`) and the DynamoDB option is being deprecated. DynamoDB is used here because the task asks for it.

## Task 3: Multi-account IAM
- **group1** (`engine`, `ci`): no console login profile, so programmatic access only. Both can assume roleB (trusted by user ARN).
- **group2** (`alice`, `bob`): console login profiles, password reset on first login, change-password and self-MFA permissions, and the ability to assume roleA. roleA requires MFA.
- **roleA**: `NotAction: iam:*` with `Resource: *`. This is everything except IAM. (Note: it still includes `sts:AssumeRole`.)
- **roleB**: trusted by `engine` and `ci`; its only permission is `sts:AssumeRole` on `arn:aws:iam::<B>:role/roleC`.
- **roleC** (Account B): `s3:*` on one named bucket and its objects; trust policy names only `arn:aws:iam::<A>:role/roleB`.
- Access keys are not created in Terraform (the secret would be stored in state). Create them with `aws iam create-access-key`.

### 1. Would I give `engine` and `ci` IAM users with access keys in production?
No. Long-lived keys leak (logs, laptops, repos) and rarely get rotated.
- `ci`: use OIDC federation (GitHub Actions / GitLab to an IAM role), which gives short-lived credentials and no stored secret.
- `engine`: if it is a workload, use an instance profile, ECS task role or IRSA.
- Humans: IAM Identity Center (SSO).
- If keys are truly unavoidable: tight scoping, source-IP/condition restrictions, scheduled rotation, storage in Secrets Manager, and alerting on use.

### 2. roleC trust: Account A root vs roleB's ARN
Trusting `arn:aws:iam::<A>:root` delegates the decision to Account A. Any principal in A that Account A's admins have given `sts:AssumeRole` can then assume roleC, including a compromised user or any admin, and Account B has no say. For example, roleA (`NotAction iam:*`) allows `sts:AssumeRole`, so it could assume roleC. Trusting roleB's exact ARN means Account B, the resource owner, decides that only that one role may come in. This satisfies "not anything else in Account A". Both sides must still allow it: roleB's identity policy permits the assume, and roleC's trust names roleB.

## Task 4: Least-privilege CI policy (`task4-ci-policy/ci-policy.json`)
Covers exactly: ECR push to one repo, ECS deploy to one service, read-only on one S3 bucket.

**Deliberately left out:**
- **Resource `*`** appears only where AWS has no resource-level support: `ecr:GetAuthorizationToken`, `ecs:RegisterTaskDefinition`, `ecs:DescribeTaskDefinition`.
- **No image pull/delete** (`BatchGetImage`, `GetDownloadUrlForLayer`, `BatchDeleteImage`): CI only pushes, and a compromised pipeline cannot wipe the registry.
- **No `ecr:CreateRepository`**: the repository is infrastructure, not a pipeline concern.
- **No `ecs:CreateService`, `DeleteService`, `RunTask`, `DeregisterTaskDefinition`**: CI updates an existing service only.
- **`iam:PassRole` is scoped** to the two task roles and `iam:PassedToService = ecs-tasks.amazonaws.com`. Unscoped PassRole is a privilege-escalation path. It is needed because a new task definition references those roles.
- **No S3 write/delete**: the requirement is read-only. If the bucket uses a customer-managed KMS key, add `kms:Decrypt` on that key only.
- **No CloudWatch Logs or other services**: the pipeline does not need them; runtime logging uses the task execution role.
- It is a custom inline policy, not a managed one like PowerUserAccess.

## Task 5: Find and fix the bug
Fixed code is in `task5-fix/main.tf`.

**Why it failed**
1. The trust policy principal was `arn:aws:iam::000000000000:user/roleB`. roleB is an IAM role, not a user. No such user exists. IAM resolves each principal ARN to an internal unique ID when the trust policy is saved, so `CreateRole` fails with `MalformedPolicyDocument: Invalid principal in policy`. Even if it had been accepted, a user ARN can never match the session of an assumed role, so roleB's `sts:AssumeRole` would be denied. Fix: `role/roleB`.
2. The line `role = [aws_iam_role.roleC.id](http://...)` is a Markdown link pasted into the HCL. It is not valid syntax (and the reference was mis-cased `rolec`). Fix: `role = aws_iam_role.roleC.id`.
3. `s3:*` on `Resource = "*"` gives access to every bucket, but the requirement is a single named bucket. Fix: scope to the bucket ARN and `bucket/*` (both are needed, one for bucket-level actions and one for object-level actions).

**Other cross-account notes**
- Both sides must allow it: roleB's identity policy permits `sts:AssumeRole` on roleC (Task 3), and roleC's trust policy names roleB.
- roleB must exist before this is applied. If roleB is deleted and recreated, its unique ID changes and the trust stops working until re-applied.
