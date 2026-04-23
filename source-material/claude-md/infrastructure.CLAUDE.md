# Infrastructure Guidelines

This file provides guidance for working with the infrastructure code in this repository.

## Overview

Infrastructure is managed with **Terragrunt** wrapping **Terraform** modules. Configuration is organized by environment:
- `environments/dev/` - Development environment
- `environments/prod/` - Production environment

## ECS Batch Jobs - CRITICAL

When creating or modifying ECS task definitions for batch jobs (one-time or scheduled tasks that should run once and exit), **always explicitly disable the container restart policy**.

The `terraform-aws-modules/ecs` module defaults to `restartPolicy.enabled = true`, which is appropriate for long-running services but **catastrophic for batch jobs** - the container will restart indefinitely after completing.

### Required Configuration

```hcl
container_definitions = {
  my-batch-job = {
    # ... other config ...

    # CRITICAL: Disable restart policy for batch jobs
    # Batch jobs should run once and exit, not restart when they complete
    restartPolicy = {
      enabled = false
    }
  }
}
```

### Why This Matters

- Without this, a batch job that sends emails will keep restarting and re-sending after each completion
- The default 300-second threshold means the job must run for 5+ minutes before restarts kick in
- Short test runs may not exhibit this behavior, masking the issue until production
- This caused duplicate email sends in production (Jan 2026) - the job restarted 5 times before being stopped

### Files to Check

- `environments/dev/ecs/terragrunt.hcl`
- `environments/prod/ecs/terragrunt.hcl`

## SSM Bastion for RDS Access

The production RDS Multi-AZ DB cluster is VPC-only (no public endpoint). Developer access uses SSM Session Manager port forwarding through a bastion EC2 instance.

### Architecture

```
Developer laptop → SSM Session Manager → Bastion EC2 (public subnet) → RDS cluster (database subnet)
```

- **Bastion**: `t4g.nano` in a public subnet, Amazon Linux 2023 with SSM agent
- **No SSH keys**: All access via SSM (IAM-authenticated)
- **No inbound ports**: Security group allows only HTTPS outbound (for SSM APIs)
- **Config**: `environments/prod/bastion/`

### Deploying the Bastion

```bash
cd infrastructure/environments/prod/bastion
terragrunt plan   # Review
terragrunt apply  # Deploy
```

After deploy, note the `instance_id` output — this is the SSM target.

### Developer Usage

Use `scripts/db-connect.sh` which auto-discovers the bastion and handles tunneling:

```bash
# Interactive psql (auto-tunnels)
./scripts/db-connect.sh prod

# Open tunnel for GUI tools (Drizzle Studio, etc.)
./scripts/db-connect.sh prod --tunnel
```

Or manually:
```bash
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<cluster-endpoint>"],"portNumber":["5432"],"localPortNumber":["5432"]}'
```

### Troubleshooting

- **"No running SSM bastion instance found"**: Check that the bastion EC2 is running in the AWS console
- **SSM session fails**: Verify `aws sso login --profile rootnote` and that the Session Manager plugin is installed
- **Bastion AMI updates**: The AMI is looked up dynamically (latest Amazon Linux 2023). To update: `terragrunt apply` will pick up the newest AMI

## Common Patterns

### Adding a New ECS Service

1. Add the service configuration to `environments/{env}/ecs/terragrunt.hcl`
2. For long-running services: no special restart config needed (module default is fine)
3. For batch jobs: **always add `restartPolicy = { enabled = false }`**
4. Run `terragrunt plan` to verify changes
5. Run `terragrunt apply` to deploy

### Parameter Store Secrets

- Secrets are stored in AWS Systems Manager Parameter Store
- Configuration is in `environments/{env}/parameter-store/`
- ECS tasks reference secrets via ARNs in the `secrets` block

### Scheduled Tasks (EventBridge)

- Scheduled ECS tasks are configured in `environments/{env}/ecs-scheduled-tasks/`
- EventBridge rules use the task definition family (without revision) to always use LATEST
- This means any task definition update takes effect on the next scheduled run
