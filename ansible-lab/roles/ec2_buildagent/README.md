# EC2 Build Agent Role

Provisions an AWS EC2 instance for hosting a GitHub Actions self-hosted runner.

## Features

- **IAM Instance Profile**: Uses IAM instance profile instead of static AWS keys for secure credential management
- **Security Group Management**: Creates security group with inbound SSH and outbound package manager access
- **Block/Rescue/Always**: Demonstrates comprehensive error handling with graceful cleanup on failure
- **SSH Connectivity Verification**: Waits for SSH port to be available before returning control
- **Comprehensive Tagging**: Tags all resources for cost tracking and lifecycle management
- **Idempotent**: Can be safely re-run; security group is created only if needed

## Requirements

- `amazon.aws` collection installed
- AWS credentials configured (IAM instance profile recommended for control node)
- IAM instance profile with appropriate permissions pre-created
- EC2 key pair already exists in target region
- Ubuntu 22.04 LTS AMI ID available in target region

## Variables

### Required
- `key_pair_name`: Name of EC2 key pair for SSH access
- `iam_instance_profile`: Name of pre-created IAM instance profile

### Common (Override as needed)
- `aws_region`: AWS region (default: us-east-1)
- `instance_type`: EC2 instance type (default: t3.medium)
- `ami_id`: Ubuntu 22.04 LTS AMI ID (default: us-east-1 AMI, update for other regions)
- `ssh_allowed_cidr`: CIDR block allowed SSH access (default: 0.0.0.0/0, restrict for security)
- `environment`: Environment tag (default: dev)
- `owner`: Owner tag (default: DevOps)

## Usage Example

```yaml
---
- name: Provision GitHub Runner on EC2
  hosts: localhost
  connection: local
  gather_facts: true
  vars:
    key_pair_name: my-ec2-keypair
    iam_instance_profile: github-runner-ec2-profile
    ssh_allowed_cidr: 203.0.113.0/24  # Restrict SSH to your office IP
    environment: production
  roles:
    - ec2_buildagent
```

## Output

Role registers `ec2_instance` variable containing:
- `instances[0].instance_id`: EC2 instance ID
- `instances[0].public_ip_address`: Public IP for SSH access
- `instances[0].private_ip_address`: Private IP
- `instances[0].state.name`: Instance state (running, stopped, etc.)

Use this in subsequent plays to configure the instance:

```yaml
- name: Configure instance
  hosts: "{{ ec2_instance.instances[0].public_ip_address }}"
  roles:
    - build_agent_tools
    - github_runner
```

## Error Handling

The role uses block/rescue/always pattern:

- **Block**: Attempts to create security group and launch instance
- **Rescue**: 
  - Logs the error
  - Cleans up partially-created security group (if instance failed)
  - Fails with actionable troubleshooting steps
- **Always**: 
  - Displays instance details (name, ID, IPs, state)
  - Provides summary for debugging

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `Security group 'xxx' already exists` | SG name collision | Use different `sg_name` or manually delete old SG |
| `Invalid IAM instance profile` | Profile doesn't exist or no permissions | Verify IAM profile name and permissions |
| `SSH timeout` | Security group rules incorrect | Check outbound rules allow port 22 egress |
| `AMI not found` | Wrong AMI ID for region | Get correct Ubuntu 22.04 AMI for your region |

## Dependencies

- Requires `amazon.aws` collection (2.1.0+)
- Requires AWS credentials (env vars: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, or IAM role)

## Tags

- `ec2_buildagent`: All tasks in this role
- `security`: Security group creation task
- `compute`: Instance launch task
- `connectivity`: SSH wait task
- `cleanup`: Rescue cleanup task
- `summary`: Always display task

Run only security tasks: `ansible-playbook -t security playbooks/provision-github-runner.yaml`

## Notes

- Instance is created with default VPC if `vpc_id` not specified
- Public IP assignment enabled by default (required for external GitHub access)
- Instance tags include creation timestamp for tracking
- SSH key must exist in region; key is not created by this role
