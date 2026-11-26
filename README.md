# terraform-eks-secure-baseline

A secure-by-default AWS EKS landing zone in Terraform, with a CI pipeline that
blocks insecure changes before they merge.

It is built to be **reviewed and planned, not left running**: there is no
`apply` job and no AWS account is required for CI to pass.

```
envs/dev/                    root module: VPC + EKS + S3 + IAM wiring
modules/s3-secure-bucket/    KMS, versioning, TLS-only policy, no public access
modules/github-oidc-role/    keyless GitHub Actions -> AWS (no access keys)
modules/pod-identity-role/   least-privilege IAM for one Kubernetes ServiceAccount
.github/workflows/           fmt, validate, tflint, Trivy, Checkov, OIDC plan
```

## Security controls

| Area | Control | Where |
|---|---|---|
| Identity | GitHub Actions authenticates with **OIDC**; trust is pinned to `repo:<org>/<repo>:environment:<env>`, and the module rejects wildcard subjects | `modules/github-oidc-role` |
| Identity | Workloads use **EKS Pod Identity**, scoped to one namespace/ServiceAccount, with `aws:SourceArn` to prevent confused-deputy use | `modules/pod-identity-role` |
| Identity | Cluster access through **EKS access entries** (`authentication_mode = "API"`); the creator gets no implicit admin | `envs/dev/main.tf` |
| Identity | IAM policies are scoped to a single S3 prefix, a single ECR namespace and a single cluster | `envs/dev/main.tf` |
| Data | Kubernetes Secrets are envelope-encrypted with a customer-managed **KMS** key (rotation on) | `aws_kms_key.eks` |
| Data | S3: SSE-KMS with bucket keys, versioning, **TLS 1.2+ only**, public access blocked, ACLs disabled | `modules/s3-secure-bucket` |
| Data | Encrypted gp3 node volumes; Bottlerocket AMI (minimal, immutable host OS) | node group |
| Network | Nodes in private subnets; control plane ENIs in intra subnets; **private API endpoint**, public endpoint only with an explicit CIDR allow-list | `module.vpc`, `module.eks` |
| Network | VPC CNI **NetworkPolicy enforcement** turned on, so Kubernetes `NetworkPolicy` objects actually apply | `addons.vpc-cni` |
| Network | Default security group stripped of all rules | `module.vpc` |
| Host | **IMDSv2 required** with hop limit 1: pods cannot steal node credentials | `metadata_options` |
| Audit | All five EKS control plane log types (incl. `audit`) and **VPC flow logs** to CloudWatch, 90-day retention | `module.eks`, `module.vpc` |
| State | S3 backend with encryption and native lockfile | `envs/dev/versions.tf` |

## Pipeline

```
pull_request ──► lint ───────► fmt -check, validate (every module), tflint + AWS ruleset
             ──► security ───► Trivy config  ──► SARIF ──► GitHub Security tab
             │                 Trivy gate (HIGH/CRITICAL fails the build)
             │                 Checkov (second opinion, SARIF, non-blocking)
             └─► plan (dev) ─► OIDC into AWS ──► terraform plan ──► artifact
                               (only when the repo variable AWS_PLAN_ROLE_ARN is set)
schedule (weekly) ─► rescans main so newly published checks surface on old code
```

- Every third-party action is **pinned to a commit SHA**; Dependabot keeps them
  and the registry modules up to date.
- The workflow token defaults to `contents: read`; only the jobs that need
  `security-events: write` or `id-token: write` get them.
- Registry modules are downloaded before scanning, so Trivy checks the
  resources that will really be created, not just the wrapper code.

## Risk acceptance, not silent suppression

Trivy flags the EKS node security group's open egress (`AWS-0104`, CRITICAL).
Nodes need it to pull images through NAT. Rather than lowering the threshold,
the exception lives in [`.trivyignore.yaml`](.trivyignore.yaml) with a
justification, an owner, the production fix (VPC endpoints + egress firewall)
and an **expiry date**. Once that date passes the finding fails CI again and
has to be reviewed.

## Run it locally

```bash
./scripts/local-checks.sh        # same gates as CI; tflint/Trivy run via Docker
```

To plan against a real account:

```bash
cd envs/dev
cp backend.hcl.example backend.hcl   # point at your state bucket
terraform init -backend-config=backend.hcl
terraform plan -var='admin_role_arns=["arn:aws:iam::123456789012:role/Admin"]'
```

To enable the CI plan job, deploy `modules/github-oidc-role` once with a
read-only policy, then set the repository variables `AWS_PLAN_ROLE_ARN`,
`TF_STATE_BUCKET` and (optionally) `AWS_REGION`.

## Production hardening

These are left out of dev on purpose, for cost:

- NAT gateway per AZ; VPC interface endpoints for ECR/S3/STS/EKS/Logs
- AWS Network Firewall or a proxy egress allow-list (closes the AWS-0104 exception)
- GuardDuty EKS Runtime Monitoring and Security Hub
- SCPs / permissions boundary on the CI role (`permissions_boundary_arn` is supported)
- Separate state, account and OIDC subject per environment
