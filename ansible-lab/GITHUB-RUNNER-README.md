# GitHub Actions Self-Hosted Runner Provisioning with Ansible

Complete Ansible solution for provisioning and managing GitHub Actions self-hosted runners on AWS EC2 instances with Docker, Kubernetes tools, AWS CLI, .NET, Maven, Node.js, and Python.

## Overview

This Ansible lab provides a comprehensive, production-ready solution for:

1. **EC2 Provisioning** - Launch instances with IAM instance profiles (no static keys)
2. **Build Tools Installation** - Docker, kubectl, Helm, AWS CLI v2, .NET SDK, Maven, Node.js, Python
3. **GitHub Runner Registration** - Secure PAT token handling with systemd service management
4. **Graceful Teardown** - Clean deregistration and resource cleanup

**Key Features:**
- ✓ IAM instance profiles instead of static AWS keys
- ✓ Block/rescue/always error handling with graceful degradation
- ✓ Secure GitHub PAT token management (wrapped with `no_log`)
- ✓ Idempotent operations (safe to re-run)
- ✓ Fact-based OS detection (Ubuntu, Debian, Amazon Linux)
- ✓ Handlers for service management
- ✓ Comprehensive validation and troubleshooting guides

## Architecture

```
provision-github-runner.yaml
├── Phase 1: EC2 Provisioning (ec2_buildagent role)
│   ├── Create security group with SSH + DNS egress
│   ├── Launch EC2 instance with IAM profile
│   ├── Wait for SSH connectivity
│   └── Block/rescue/always for error handling
│
├── Phase 2: Tool Installation (build_agent_tools role)
│   ├── Setup prerequisites (git, curl, unzip, jq)
│   ├── Install Docker CE
│   ├── Install Kubernetes tools (kubectl, Helm)
│   ├── Install AWS CLI v2
│   ├── Install build tools (.NET, Maven, Node.js, Python)
│   └── Each tool wrapped in block/rescue/always
│
└── Phase 3: GitHub Runner Setup (github_runner role)
    ├── Download latest runner from GitHub API
    ├── Extract runner to working directory
    ├── Register with GitHub (PAT protected with no_log)
    ├── Create systemd service with auto-restart
    └── Validate service running
```

## File Structure

```
ansible-lab/
├── roles/
│   ├── ec2_buildagent/              # Phase 1: EC2 provisioning
│   │   ├── tasks/main.yml           # Block/rescue/always EC2 launch
│   │   ├── defaults/main.yml        # Instance config, security group
│   │   ├── vars/main.yml            # Polling timeouts
│   │   ├── handlers/main.yml
│   │   ├── meta/main.yml
│   │   └── README.md
│   │
│   ├── build_agent_tools/           # Phase 2: Build tools
│   │   ├── tasks/
│   │   │   ├── main.yml             # Orchestrator with conditional includes
│   │   │   ├── setup_prerequisites.yml
│   │   │   ├── install_docker.yml
│   │   │   ├── install_kubernetes_tools.yml
│   │   │   ├── install_aws_cli.yml
│   │   │   └── install_build_tools.yml
│   │   ├── defaults/main.yml        # Version pins, install flags
│   │   ├── vars/main.yml            # Download URLs
│   │   ├── handlers/main.yml
│   │   ├── meta/main.yml
│   │   └── README.md
│   │
│   └── github_runner/               # Phase 3: GitHub runner registration
│       ├── tasks/
│       │   ├── main.yml             # Registration logic
│       │   └── deregister.yml       # Cleanup logic
│       ├── templates/
│       │   ├── github-runner.service.j2    # Systemd unit
│       │   └── runner-config-env.j2        # Environment file
│       ├── defaults/main.yml        # Runner config, GitHub URLs
│       ├── vars/main.yml            # Service paths, timeouts
│       ├── handlers/main.yml
│       ├── meta/main.yml
│       └── README.md
│
├── playbooks/
│   ├── provision-github-runner.yaml  # Main provisioning (calls 3 roles)
│   ├── teardown-github-runner.yaml   # Cleanup and termination
│   └── validate-github-runner.yaml   # Validation and testing
│
├── inventory/
│   ├── hosts                        # Static inventory
│   ├── aws_ec2.yaml                 # Dynamic AWS inventory
│   └── group_vars/
│       └── github_runners/
│           ├── github_runners.yml   # Group defaults
│           └── vault.yml.example    # Template for encrypted vault
│
└── README.md                        # This file
```

## Quick Start

### Prerequisites

**Local (Control Node):**
- Ansible 2.9+
- `amazon.aws` collection: `ansible-galaxy collection install amazon.aws`
- AWS CLI configured with credentials
- SSH key pair created in target AWS region

**Remote (EC2 Instance):**
- Ubuntu 22.04 LTS, 24.04, Debian 11+, or Amazon Linux 2
- Will be automatically created by playbook

### Step 1: Set Up GitHub PAT Token (Vault)

Create encrypted vault file with GitHub credentials:

```bash
# Create vault file
ansible-vault create inventory/group_vars/github_runners/vault.yml

# Add content (paste into editor):
vault_github_pat_token: "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
vault_github_repo_url: "https://github.com/myorg/myrepo"

# Exit editor (Ctrl+D), then verify encryption:
cat inventory/group_vars/github_runners/vault.yml
# Should show encrypted content like: $ANSIBLE_VAULT;1.1;AES256;...
```

### Step 2: Configure Runner Defaults

Update inventory defaults (optional):

```bash
# Edit group variables
vim inventory/group_vars/github_runners.yml

# Customize:
# - runner_labels (e.g., add production, docker, linux)
# - aws_region (default: us-east-1)
# - instance_type (default: t3.medium)
# - tool versions (kubectl_version, maven_version, etc.)
```

### Step 3: Provision Runner

```bash
# Run provisioning playbook
ansible-playbook playbooks/provision-github-runner.yaml \
  -i inventory/hosts \
  --vault-password-file=.vault_pass \
  -e "key_pair_name=my-ec2-key"

# Or prompt for vault password:
ansible-playbook playbooks/provision-github-runner.yaml \
  -i inventory/hosts \
  --ask-vault-pass \
  -e "key_pair_name=my-ec2-key"
```

**Output:** Displays EC2 instance IP, runner name, and next steps.

### Step 4: Verify Runner Registration

```bash
# Validate installation
ansible-playbook playbooks/validate-github-runner.yaml \
  -i inventory/hosts \
  --vault-password-file=.vault_pass

# Check GitHub UI
# Navigate to: Settings > Actions > Runners
# Verify runner appears with status "Idle"
```

### Step 5: Test with GitHub Actions Workflow

Create test workflow (`.github/workflows/test-runner.yml`):

```yaml
name: Test Self-Hosted Runner
on: [push]
jobs:
  test:
    runs-on: [self-hosted, linux]
    steps:
      - name: System info
        run: |
          echo "Hostname: $(hostname)"
          echo "OS: $(lsb_release -d)"
          echo "Memory: $(free -h)"
      
      - name: Test Docker
        run: docker run --rm alpine echo "Docker works!"
      
      - name: Test build tools
        run: |
          docker --version
          kubectl version --client
          aws --version
          dotnet --version
          node --version
          python3 --version
```

Push to repo and verify workflow runs on your self-hosted runner.

## Detailed Usage

### Full Provisioning Playbook

```bash
# Basic run
ansible-playbook playbooks/provision-github-runner.yaml \
  -i inventory/hosts \
  --vault-password-file=.vault_pass \
  -e "key_pair_name=my-ec2-key"

# With custom variables
ansible-playbook playbooks/provision-github-runner.yaml \
  -i inventory/hosts \
  --vault-password-file=.vault_pass \
  -e "key_pair_name=my-ec2-key" \
  -e "instance_type=t3.large" \
  -e "aws_region=eu-west-1" \
  -e "environment=production"

# Run specific tags only
ansible-playbook playbooks/provision-github-runner.yaml \
  -i inventory/hosts \
  --vault-password-file=.vault_pass \
  -e "key_pair_name=my-ec2-key" \
  -t ec2,security  # Only EC2 + security group tasks

# Dry run (check mode)
ansible-playbook playbooks/provision-github-runner.yaml \
  -i inventory/hosts \
  --vault-password-file=.vault_pass \
  -e "key_pair_name=my-ec2-key" \
  --check
```

### Teardown (Cleanup)

```bash
# Clean deregistration and instance termination
ansible-playbook playbooks/teardown-github-runner.yaml \
  -i inventory/hosts \
  --vault-password-file=.vault_pass \
  -e "runner_instance_id=i-xxxxxxxxx"

# Without vault (if PAT passed via environment):
GITHUB_PAT_TOKEN="ghp_xxxxx" ansible-playbook playbooks/teardown-github-runner.yaml \
  -i inventory/hosts \
  -e "runner_instance_id=i-xxxxxxxxx" \
  -e "github_pat_token=$GITHUB_PAT_TOKEN"
```

### Validation Playbook

```bash
# Run all validation checks
ansible-playbook playbooks/validate-github-runner.yaml \
  -i inventory/hosts \
  --vault-password-file=.vault_pass

# Validate specific tags
ansible-playbook playbooks/validate-github-runner.yaml \
  -i inventory/hosts \
  --vault-password-file=.vault_pass \
  -t docker,kubernetes,aws  # Only check Docker, K8s, AWS CLI
```

### Manual Verification

```bash
# SSH into instance
ssh -i ~/.ssh/my-ec2-key.pem ubuntu@<public-ip>

# Check runner service
sudo systemctl status github-runner
sudo journalctl -u github-runner -f

# Verify tools
docker --version
kubectl version --client
helm version
aws --version
dotnet --version
mvn --version
node --version
python3 --version

# Check runner config
cat /home/github-runner/runner/.runner
```

## Variables Reference

### Required Variables

Pass these via `-e` flag or vault:

```yaml
# AWS Configuration
key_pair_name: "my-ec2-key"              # EC2 key pair name (REQUIRED)

# GitHub Configuration (from vault)
vault_github_pat_token: "ghp_xxxxxxx"    # GitHub PAT (REQUIRED)
vault_github_repo_url: "https://..."     # Repository URL (REQUIRED)
```

### Optional Variables

Defined in inventory or playbook:

```yaml
# AWS
aws_region: us-east-1                    # AWS region (default: us-east-1)
instance_type: t3.medium                 # EC2 type (default: t3.medium)
environment: production                  # Environment tag (default: production)
ssh_allowed_cidr: 0.0.0.0/0              # SSH access CIDR (default: any)

# Runner Configuration
runner_name: "prod-runner"               # Display name in GitHub UI
runner_labels:                           # Job targeting labels
  - self-hosted
  - linux
  - docker
  - aws

# Tool Versions
kubectl_version: v1.27.0                 # Kubernetes version
helm_version: v3.12.0                    # Helm version
maven_version: 3.9.2                     # Maven version
dotnet_version: 7.0                      # .NET version
nodejs_version: v18.17.0                 # Node.js version

# Installation Flags
install_docker: true                     # Install Docker
install_kubernetes_tools: true           # Install kubectl/Helm
install_aws_cli: true                    # Install AWS CLI
install_build_tools: true                # Install .NET/Maven/Node/Python
```

## Idempotency & Re-runs

The playbooks are designed to be **idempotent** and safe to re-run:

```bash
# Safe to re-run: skips already-installed tools
ansible-playbook playbooks/provision-github-runner.yaml \
  -i inventory/hosts \
  --vault-password-file=.vault_pass \
  -e "key_pair_name=my-ec2-key"

# Re-running on same instance:
# - Skips EC2 creation if already exists
# - Skips tool installation if already at target version
# - Skips GitHub registration if already configured
```

**What is Idempotent:**
- EC2 instance creation (checks if already exists)
- Security group creation (checks if already exists)
- Tool installation (checks versions)
- GitHub registration (checks if already configured)

**What is NOT Idempotent (by design):**
- Playbook outputs/summaries (always displayed)
- Service restarts (if service file changes)
- Debug tasks (always executed)

## Error Handling & Troubleshooting

### Block/Rescue/Always Pattern

All critical operations use block/rescue/always for robust error handling:

```yaml
block:
  - Download tool
  - Install tool
rescue:
  - Log error message
  - Continue with next tool (graceful degradation)
always:
  - Display status summary
```

**Benefits:**
- Partial success: If Docker fails, Python still installs
- No orphaned resources: Rescue blocks clean up partial state
- Clear error messages: Always block displays actionable info

### Common Errors & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `Security group 'xxx' already exists` | SG name collision | Use different name or delete old SG |
| `Invalid IAM instance profile` | Profile doesn't exist | Pre-create IAM role with EC2 permissions |
| `SSH timeout` | Security group rules wrong | Verify outbound HTTPS for package managers |
| `GitHub API 401 Unauthorized` | Invalid/expired PAT | Regenerate PAT with correct scopes |
| `Runner already exists` | Name collision in GitHub | Use unique runner_name or delete existing |
| `Docker installation fails` | No internet access | Check security group outbound rules |
| `Module amazon.aws not found` | Collection not installed | Run: `ansible-galaxy collection install amazon.aws` |

### Debug Mode

Run playbooks with verbose output:

```bash
# Verbose (shows more details)
ansible-playbook playbooks/provision-github-runner.yaml \
  -i inventory/hosts \
  --vault-password-file=.vault_pass \
  -e "key_pair_name=my-ec2-key" \
  -v

# Very verbose (shows all tasks)
ansible-playbook playbooks/provision-github-runner.yaml \
  -i inventory/hosts \
  --vault-password-file=.vault_pass \
  -e "key_pair_name=my-ec2-key" \
  -vvv
```

### Check Logs

```bash
# SSH into instance and view service logs
ssh -i ~/.ssh/my-ec2-key.pem ubuntu@<public-ip>
sudo journalctl -u github-runner -f  # Follow logs
sudo journalctl -u github-runner -n 100  # Last 100 lines

# Check system logs
sudo tail -f /var/log/syslog

# Check Ansible logs (on control node)
cat /var/log/ansible.log  # If ansible logging configured
```

## Security Best Practices

### GitHub PAT Token

1. **Scope Minimization**: Only grant required scopes:
   - `repo` - Full control of private repositories
   - `admin:org_hook` - Write access to webhooks
   - `workflow` - Update workflows

2. **Token Storage**:
   - ✓ Store in Ansible vault (encrypted at rest)
   - ✓ Use `--vault-password-file` with restricted permissions
   - ✗ Never commit PAT to git
   - ✗ Never pass via CLI without encryption

3. **Token Rotation**:
   - Rotate every 90 days
   - Revoke old token after verification
   - Test new token before deleting old one

4. **no_log Protection**:
   - All tasks using PAT have `no_log: true`
   - Token never appears in logs or output
   - Sanitized from error messages

### IAM Security

1. **Instance Profile** (not static keys):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "ec2:DescribeInstances",
           "ec2:DescribeTags",
           "s3:GetObject"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

2. **Control Node Credentials**:
   - Use AWS profiles: `export AWS_PROFILE=production`
   - Use assumed roles: `sts:AssumeRole`
   - Rotate access keys regularly

### Systemd Service Sandboxing

```ini
[Service]
NoNewPrivileges=true    # Prevent privilege escalation
PrivateTmp=true         # Isolated temporary directory
ProtectHome=true        # Protect home directory
```

### Network Security

1. **Security Group**:
   - SSH (22): Restrict to known IPs/VPNs
   - HTTP/HTTPS (80/443): Egress only (for package managers)
   - DNS (53): Egress only (UDP/TCP)

2. **SSH Key Management**:
   - Use EC2 key pairs (not password auth)
   - Rotate keys regularly
   - Restrict permissions: `chmod 600 ~/.ssh/key.pem`

## Performance Tuning

### First Provisioning Time

Typical timeline:
- EC2 launch & SSH wait: 2-3 minutes
- Tool installation: 15-20 minutes
- GitHub registration: 1-2 minutes
- **Total: ~20-25 minutes**

### Reducing Install Time

1. **Skip unnecessary tools**:
   ```bash
   -e "install_kubernetes_tools=false" \
   -e "install_dotnet=false"
   ```

2. **Use pre-built AMI**:
   - Bake tools into custom AMI
   - Run role only for registration

3. **Parallel provisioning**:
   - Use Ansible Tower/AWX for multiple instances
   - Create 10 runners simultaneously

### Monitoring Performance

```bash
# Check instance metrics during provisioning
watch -n 5 'aws ec2 describe-instances --instance-ids i-xxxxx --query "Instances[0].[State.Name,CpuOptions.CoreCount]"'

# SSH and check during tool install
top -b -n 1 | head -20
df -h
```

## Advanced Usage

### Custom AMI

Pre-bake tools into AMI to speed up provisioning:

```bash
# Update ami_id in defaults/main.yml
ami_id: "ami-my-custom-image"

# Playbook will use pre-built image with all tools
# Registration takes ~5 minutes instead of 25
```

### Multiple Runners

Provision multiple runners in parallel:

```bash
# Create runners in loop
ansible-playbook playbooks/provision-github-runner.yaml \
  -i inventory/hosts \
  --vault-password-file=.vault_pass \
  -e "key_pair_name=my-ec2-key" \
  -e "{{ item }}" \
  --tags "create-ec2"
  with_items:
    - runner_name: runner-1
    - runner_name: runner-2
    - runner_name: runner-3
```

### GitHub Enterprise

Support for GitHub Enterprise Server:

```yaml
# inventory/group_vars/github_runners.yml
github_api_url: "https://github-enterprise.company.com/api/v3"
runner_releases_url: "https://github-enterprise.company.com/api/v3/repos/github/runner/releases"
```

### Infrastructure as Code Integration

Use with Terraform:

```hcl
# terraform/main.tf
resource "aws_instance" "runner" {
  ami               = data.aws_ami.ubuntu.id
  instance_type     = "t3.medium"
  iam_instance_profile = aws_iam_instance_profile.runner.name

  tags = {
    Name = "github-runner"
  }
}

# Then configure with Ansible:
# ansible-playbook playbooks/provision-github-runner.yaml
```

## Monitoring & Observability

### Service Health

```bash
# Check service status
systemctl status github-runner

# View recent logs
journalctl -u github-runner -n 50 --no-pager

# Follow logs live
sudo journalctl -u github-runner -f
```

### GitHub UI Monitoring

1. **Settings > Actions > Runners**:
   - Runner status (Idle, Active, Offline)
   - Last activity timestamp
   - Job history

2. **Settings > Actions > Workflow runs**:
   - View which runner executed job
   - Execution time and resources used

### CloudWatch Integration (Optional)

```bash
# Install CloudWatch agent on instance
curl https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O
dpkg -i -E ./amazon-cloudwatch-agent.deb

# Configure to send github-runner service logs to CloudWatch
```

## Cost Optimization

### EC2 Instance Selection

| Instance Type | vCPU | Memory | Use Case | Cost/hour |
|---------------|------|--------|----------|-----------|
| t3.medium | 2 | 4 GB | Light workloads, testing | ~$0.042 |
| t3.large | 2 | 8 GB | Standard builds | ~$0.084 |
| t3.xlarge | 4 | 16 GB | Heavy builds, parallel jobs | ~$0.168 |
| m5.large | 2 | 8 GB | Production workloads | ~$0.096 |

### Cost Reduction Strategies

1. **Use t3 instances**: Burstable performance, lower cost
2. **Spot instances**: Up to 70% discount (for CI jobs, acceptable for interruptions)
3. **Scheduled provisioning**: Launch only during business hours
4. **Auto-scaling**: Provision on-demand based on workflow queue

### Estimated Monthly Costs

```
Instance Type: t3.medium
Hours per month: 730 (24/7)
Cost per hour: $0.042
Monthly compute: $30.66

Network: $0 (egress via NAT Gateway: ~$0.05/GB)
Storage: $0.50 (30 GB EBS volume)

Total: ~$31/month
(Spot: ~$10/month; Scheduled 9-5 EST: ~$8/month)
```

## Contributing & Customization

### Adding Custom Tools

1. Create new subtask file in `build_agent_tools/tasks/`:
   ```yaml
   # roles/build_agent_tools/tasks/install_custom_tool.yml
   ---
   - name: Install Custom Tool
     block:
       - name: Download tool
       - name: Install tool
     rescue:
       - name: Log failure
     tags: [custom_tool]
   ```

2. Include in main.yml:
   ```yaml
   - name: Include custom tool installation
     ansible.builtin.include_tasks: install_custom_tool.yml
     when: install_custom_tool | default(true)
   ```

3. Add variable to defaults/main.yml:
   ```yaml
   install_custom_tool: true
   ```

### Modifying Runner Configuration

Update `inventory/group_vars/github_runners.yml` or use `-e` flag:

```bash
ansible-playbook playbooks/provision-github-runner.yaml \
  -i inventory/hosts \
  --vault-password-file=.vault_pass \
  -e "key_pair_name=my-ec2-key" \
  -e "runner_labels=[self-hosted,linux,docker,custom-label]" \
  -e "instance_type=t3.large"
```

## License

MIT-0

## Support & Troubleshooting

For issues:

1. Check role README files for specific guidance
2. Review error messages in task output
3. Check logs: `journalctl -u github-runner`
4. Enable verbose mode: `-vvv`
5. Review GitHub Actions runner documentation: https://docs.github.com/en/actions/hosting-your-own-runners

## Appendix: IAM Policy for Control Node

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeImages",
        "ec2:DescribeSecurityGroups",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:CreateTags",
        "ec2:DescribeTags",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
```

---

**Last Updated**: 2024-09-02  
**Version**: 1.0  
**Maintainer**: Ansible Lab
