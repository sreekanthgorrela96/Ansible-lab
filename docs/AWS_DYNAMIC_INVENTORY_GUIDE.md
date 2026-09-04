# AWS Dynamic Inventory with SSM Connection Plugin - Complete Guide

## Overview

This guide demonstrates a production-ready AWS dynamic inventory setup using:
- **amazon.aws.aws_ec2** inventory plugin for dynamic host discovery
- **amazon.aws.aws_tags** converted to **keyed_groups** for intelligent grouping
- **community.aws.aws_ssm** connection plugin for secure sessionless connections
- **Group variables hierarchy** for environment and role-based configuration
- **Inventory caching** for performance and API rate limit protection
- **Safe --limit patterns** for environment isolation and accident prevention

## Architecture

```
AWS EC2 Instances (with tags: Environment, Role, Name)
        ↓
[amazon.aws.aws_ec2 plugin]
        ↓
Keyed Groups:
  ├── env_dev, env_qa, env_uat, env_stg, env_prod
  ├── role_webserver, role_database, role_loadbalancer
  └── tag_Name_<instance_name>
        ↓
Group Variables Precedence:
  1. inventory/group_vars/all.yml (SSM connection settings)
  2. inventory/group_vars/env_*.yml (environment-specific)
  3. inventory/group_vars/role_*.yml (role-specific)
  4. inventory/host_vars/ (host-specific overrides)
        ↓
Ansible Tasks via SSM Session Manager
        (No SSH, No port 22, IAM-authenticated)
```

## Prerequisites

### 1. Install Required Collections

```bash
ansible-galaxy collection install amazon.aws community.aws
```

Verify installation:
```bash
ansible-galaxy collection list amazon.aws community.aws
```

### 2. AWS Credentials Configuration

The inventory plugin requires AWS credentials with EC2 and SSM permissions.

#### Option A: AWS CLI Profile (Recommended)
```bash
aws configure --profile ansible-user
# Enter AWS Access Key ID
# Enter AWS Secret Access Key
# Enter Default region name: us-east-1
# Enter Default output format: json
```

Then reference in playbook:
```bash
ansible-playbook site.yml -i inventory/aws_ec2.yaml -e "ansible_aws_profile=ansible-user"
```

#### Option B: Environment Variables
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

#### Option C: IAM Role (Recommended for CI/CD)
If running from an EC2 instance with an IAM role, credentials are automatically discovered.

### 3. IAM Permissions Required

Minimum IAM policy for dynamic inventory and SSM:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EC2DiscoveryPermissions",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeTags",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets"
            ],
            "Resource": "*"
        },
        {
            "Sid": "SSMSessionPermissions",
            "Effect": "Allow",
            "Action": [
                "ssm:StartSession",
                "ssm:TerminateSession",
                "ssm:ResumeSession",
                "ssm:DescribeSessions",
                "ssm:GetConnectionStatus",
                "ec2-messages:GetMessages",
                "ec2messages:GetMessages",
                "ssmmessages:CreateControlChannel",
                "ssmmessages:CreateDataChannel",
                "ssmmessages:OpenControlChannel",
                "ssmmessages:OpenDataChannel"
            ],
            "Resource": "*"
        },
        {
            "Sid": "SSMInstanceProfile",
            "Effect": "Allow",
            "Action": [
                "ssm:UpdateInstanceInformation",
                "ec2messages:GetMessages",
                "ec2-messages:GetMessages"
            ],
            "Resource": "*"
        }
    ]
}
```

### 4. EC2 Instances Setup

Each EC2 instance must have:

1. **IAM Instance Role** with `AmazonSSMManagedInstanceCore` policy:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssmmessages:CreateControlChannel",
                "ssmmessages:CreateDataChannel",
                "ssmmessages:OpenControlChannel",
                "ssmmessages:OpenDataChannel",
                "ec2messages:GetMessages"
            ],
            "Resource": "*"
        }
    ]
}
```

2. **SSM Agent** installed and running:
   - Amazon Linux 2, Amazon Linux, Ubuntu 16.04+: Pre-installed
   - Verify: `systemctl status amazon-ssm-agent`

3. **AWS Tags** for grouping:
   - `Environment`: dev, qa, uat, stg, or prod
   - `Role`: webserver, database, loadbalancer, etc.
   - `Name`: Descriptive instance name

## Configuration Files

### 1. Inventory Plugin: `inventory/aws_ec2.yaml`

```yaml
plugin: amazon.aws.aws_ec2
aws_profile: default          # Use AWS CLI profile
regions:
  - us-east-1
  - us-west-2
filters:
  instance-state-name: running

compose:
  ansible_host: private_ip_address    # Use private IP for SSM
  public_ip: public_ip_address        # Store public IP for reference
  env_tag: ec2_tags.get("Environment", "unknown")
  role_tag: ec2_tags.get("Role", "unknown")

keyed_groups:
  - key: ec2_tags.Environment
    prefix: env
    separator: _
    parent_group: environments
  
  - key: ec2_tags.Role
    prefix: role
    separator: _
    parent_group: roles

cache_plugin: jsonfile
cache_dir: .ansible/cache
cache_prefix: aws_ec2
cache_timeout: 3600
```

### 2. Global Variables: `inventory/group_vars/all.yml`

Sets up SSM connection plugin and common settings:

```yaml
ansible_connection: community.aws.aws_ssm
ansible_aws_ssm_region: us-east-1
ansible_timeout: 300
ansible_python_interpreter: /usr/bin/python3
```

### 3. Environment-Specific Variables

#### `inventory/group_vars/env_dev.yml`
- High verbosity for debugging
- SSM-only optional (fallback SSH allowed)
- Relaxed security requirements

#### `inventory/group_vars/env_prod.yml`
- Conservative timeouts
- Strict security compliance
- Requires explicit confirmation
- Full monitoring and backups
- Change management requirements

### 4. Role-Specific Variables

#### `inventory/group_vars/role_webserver.yml`
- HTTP/HTTPS ports (80, 443, 8080)
- Webserver packages and services
- SSL/TLS configuration
- Rate limiting and caching

#### `inventory/group_vars/role_database.yml`
- Database engine and ports
- Performance tuning parameters
- Backup and recovery settings
- Replication configuration

#### `inventory/group_vars/role_loadbalancer.yml`
- Load balancing algorithm
- Health check configuration
- SSL termination settings
- Rate limiting and compression

## Usage Examples

### 1. View Inventory Structure

```bash
# Display all groups created by keyed_groups
ansible-inventory -i inventory/aws_ec2.yaml --graph

# Show detailed inventory with host variables
ansible-inventory -i inventory/aws_ec2.yaml --list

# Show only production webservers
ansible-inventory -i inventory/aws_ec2.yaml --limit "env_prod:&role_webserver" --list
```

### 2. Run Playbooks with Safe Limits

```bash
# Development environment only (SAFE)
ansible-playbook playbooks/demo-dynamic-inventory.yaml \
  -i inventory/aws_ec2.yaml \
  --limit env_dev

# QA webservers only
ansible-playbook playbooks/site.yaml \
  -i inventory/aws_ec2.yaml \
  --limit "env_qa:&role_webserver"

# Multiple environments (controlled)
ansible-playbook playbooks/site.yaml \
  -i inventory/aws_ec2.yaml \
  --limit "env_dev,env_qa"

# Everything except production (safety pattern)
ansible-playbook playbooks/deploy.yaml \
  -i inventory/aws_ec2.yaml \
  --limit "all:!env_prod"

# Production with explicit confirmation
ansible-playbook playbooks/site.yaml \
  -i inventory/aws_ec2.yaml \
  --limit env_prod \
  -e "i_understand_this_is_production=true" \
  -v
```

### 3. Verify SSM Connection

```bash
# Connect to a specific host via SSM (interactive shell)
aws ssm start-session --target <instance-id>

# Run a command via SSM
aws ssm send-command \
  --instance-ids <instance-id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["echo Hello from SSM"]'
```

### 4. Force Inventory Cache Refresh

```bash
# Clear cache and rebuild
ansible-inventory -i inventory/aws_ec2.yaml --force-cache --list

# Or delete cache file
rm -rf .ansible/cache/aws_ec2_*
```

## Group Variables Precedence

Ansible applies variables in this order (first match wins):

1. **`inventory/group_vars/all.yml`** - Applied to all hosts
   - SSM connection configuration
   - Global timeouts and Python interpreter
   
2. **`inventory/group_vars/env_<env>.yml`** - Environment-specific
   - Environment name and short code
   - Timeouts and logging levels
   - Security policies
   - Monitoring settings
   
3. **`inventory/group_vars/role_<role>.yml`** - Role-specific
   - Service-specific ports and packages
   - Performance tuning
   - Application settings
   
4. **`inventory/host_vars/<hostname>.yml`** - Host-specific (if exists)
   - Per-host overrides
   
### Example: Timeout Precedence

For a host tagged with `Environment=prod` and `Role=database`:

```
1. all.yml: ansible_timeout = 300 (from all.yml)
2. env_prod.yml: ansible_timeout = 600 (override to 600)
3. role_database.yml: (no override)
Result: ansible_timeout = 600
```

## Keyed Groups Explained

### What are Keyed Groups?

Keyed groups dynamically create host groups based on EC2 tags. For example:

#### Input EC2 Instances:
```
web01: Environment=dev, Role=webserver
web02: Environment=prod, Role=webserver
db01: Environment=prod, Role=database
```

#### Generated Groups:
```
env_dev:           [web01]
env_prod:          [web02, db01]
role_webserver:    [web01, web02]
role_database:     [db01]
tag_Name_web01:    [web01]
```

### Safe Limit Patterns

These patterns combine groups using `:` (intersection) and `,` (union):

```bash
# Single environment (SAFEST)
--limit env_dev              # All dev hosts

# Environment + Role (SPECIFIC)
--limit "env_prod:&role_webserver"    # Production webservers only

# Multiple environments (CONTROLLED)
--limit "env_dev,env_qa"     # Dev and QA (not production)

# Exclusion (CAREFUL)
--limit "all:!env_prod"      # Everything except production
```

## Inventory Caching

### Why Cache?

- **Speed**: Cached inventory loads instantly vs. 10-30 seconds API calls
- **Rate Limits**: Avoid AWS API throttling (100 requests/second)
- **Cost**: Fewer API calls = fewer CloudTrail logs

### Cache Configuration

In `inventory/aws_ec2.yaml`:
```yaml
cache_plugin: jsonfile
cache_dir: .ansible/cache
cache_prefix: aws_ec2
cache_timeout: 3600  # 1 hour
```

### Cache Files

Cache files stored as:
```
.ansible/cache/
  aws_ec2_*  (hashed inventory data)
  aws_ec2_*.checksum
```

### Refresh Strategies

```bash
# Use cache (default after first run)
ansible-inventory -i inventory/aws_ec2.yaml --list

# Force refresh (ignore cache)
ansible-inventory -i inventory/aws_ec2.yaml --force-cache --list

# Clear cache entirely
rm -rf .ansible/cache/aws_ec2_*

# Check cache age
stat .ansible/cache/aws_ec2_*
```

## SSM Connection Plugin

### How It Works

1. **Ansible** connects to instance via AWS Systems Manager Session Manager
2. **Session Manager** creates a secure tunnel through AWS APIs
3. **Private IP** is used (no public IP exposure required)
4. **IAM authentication** is used (no SSH key management needed)
5. **Session logging** can be sent to S3 for compliance

### Architecture

```
Ansible Control Node
        ↓
   AWS SDK/CLI
        ↓
  AWS Systems Manager
        ↓
    Secure Tunnel
        ↓
   EC2 Instance (Private IP)
        ↓
   SSM Agent
```

### Security Benefits

✓ **No SSH port exposure** - No attack surface  
✓ **IAM-authenticated** - Uses AWS credentials  
✓ **Encrypted tunnel** - All traffic encrypted  
✓ **Session logging** - Audit trail to S3  
✓ **Works cross-VPC** - Tunnel through VPN/PrivateLink  
✓ **Bastion-less** - No jump hosts needed  

### Configuration

In `group_vars/all.yml`:
```yaml
ansible_connection: community.aws.aws_ssm
ansible_aws_ssm_region: us-east-1
ansible_aws_ssm_bucket_name: ~           # Optional: S3 bucket for logs
ansible_aws_ssm_bucket_region: us-east-1
ansible_timeout: 300
```

### Troubleshooting SSM

```bash
# Verify instance has SSM permissions
aws ssm describe-instance-information --query 'InstanceInformationList[*]'

# Check SSM Agent status
aws ssm get-command-invocation \
  --command-id <cmd-id> \
  --instance-id <instance-id>

# Test connection manually
aws ssm start-session --target <instance-id>

# Check IAM permissions for Ansible user
aws iam get-user

# Verify security group allows SSM (HTTPS 443)
aws ec2 describe-security-groups --group-ids <sg-id>
```

## Best Practices

### 1. Environment Safety

```bash
# ALWAYS use --limit with environment
✓ ansible-playbook site.yml --limit env_dev
✗ ansible-playbook site.yml  # Targets ALL hosts - DANGEROUS!

# Combine with roles for precision
✓ ansible-playbook deploy.yml --limit "env_prod:&role_webserver"
```

### 2. Production Deployments

```bash
# Test in dev first
ansible-playbook site.yml --limit env_dev --check

# Test in QA
ansible-playbook site.yml --limit env_qa --check

# Deploy to production with confirmation
ansible-playbook site.yml \
  --limit env_prod \
  -e "i_understand_this_is_production=true" \
  -v
```

### 3. Inventory Management

```bash
# Regularly refresh cache to catch new instances
ansible-inventory -i inventory/aws_ec2.yaml --force-cache --list > /tmp/inventory.json

# Schedule cache refresh
# Add to cron: 0 * * * * cd /path/to/ansible && ansible-inventory -i inventory/aws_ec2.yaml --force-cache
```

### 4. Variable Organization

```
all.yml              # SSM connection, common timeouts, Python
├── env_dev.yml     # Dev-specific: debug logging, relaxed security
├── env_qa.yml      # QA-specific: test settings
├── env_prod.yml    # Prod-specific: strict security, approvals
└── role_*.yml      # Role-specific: service configs
```

### 5. Monitoring & Compliance

```yaml
# In env_prod.yml
require_approval_for_changes: true
enable_compliance_checking: true
snapshot_before_changes: true
enable_cloudtrail_logging: true
enable_ssm_session_logging: true
```

## Troubleshooting

### Issue: "Inventory plugin (amazon.aws.aws_ec2) not found"

**Solution**: Install required collections
```bash
ansible-galaxy collection install amazon.aws community.aws
ansible-galaxy collection install boto3 botocore
```

### Issue: "Failed to connect to host: Access Denied"

**Check**:
1. AWS credentials configured: `aws sts get-caller-identity`
2. IAM user/role has EC2 and SSM permissions
3. EC2 instances have IAM instance role with SSM permissions
4. SSM Agent running: `aws ssm describe-instance-information`

### Issue: "Connection timed out"

**Solutions**:
1. Verify SSM Agent is running: `aws ssm send-command --instance-ids <id> --document-name AWS-RunShellScript --parameters commands=['systemctl status amazon-ssm-agent']`
2. Check security group allows HTTPS (443): `aws ec2 describe-security-groups --group-ids <sg-id>`
3. Increase timeout: `ansible_timeout: 600` in group_vars

### Issue: "No hosts matched"

**Check**:
1. Verify instances are running: `aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"`
2. Verify instances have required tags: `aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,Tags]'`
3. Review keyed_groups configuration in `aws_ec2.yaml`

## Advanced Topics

### Cross-Region Inventory

```yaml
# aws_ec2.yaml
regions:
  - us-east-1
  - us-west-2
  - eu-west-1
  - ap-southeast-1
```

### Tag-Based Filtering

```yaml
filters:
  instance-state-name: running
  "tag:Environment": ["dev", "qa", "uat"]
  "tag:ManagedBy": "terraform"
  "tag:CostCenter": "engineering"
```

### Custom Keyed Groups

```yaml
keyed_groups:
  # Group by tag:Environment AND tag:Role (cartesian product)
  - key: "ec2_tags.Environment ~ '-' ~ ec2_tags.Role"
    separator: "_"
  
  # Group by instance type
  - key: instance_type
    prefix: "type"
  
  # Group by availability zone
  - key: placement.availability_zone
    prefix: "az"
```

### Compose Advanced Variables

```yaml
compose:
  # Store multiple attributes
  ansible_host: private_ip_address
  public_ip: public_ip_address
  instance_id: ec2_id
  
  # Calculate derived values
  cost_center: "ec2_tags.get('CostCenter', 'unknown')"
  is_prod: "ec2_tags.get('Environment', '') == 'prod'"
  
  # Complex logic
  ssh_user: "ubuntu" if ami_launch_index == 0 else "ec2-user"
```

## Reference

### Documentation
- [amazon.aws.aws_ec2 plugin](https://docs.ansible.com/ansible/latest/collections/amazon/aws/aws_ec2_inventory.html)
- [community.aws.aws_ssm connection plugin](https://docs.ansible.com/ansible/latest/collections/community/aws/aws_ssm_connection.html)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)

### Related Playbooks
- `playbooks/demo-dynamic-inventory.yaml` - Complete demonstration
- `playbooks/create-ec2.yaml` - Create instances with required tags
- `playbooks/site.yaml` - Example multi-role deployment

### Collection Requirements
```yaml
# requirements.yml
collections:
  - name: amazon.aws
    version: ">=6.0.0"
  - name: community.aws
    version: ">=5.0.0"
  - name: community.general
    version: ">=6.0.0"
```

## Summary

This setup provides:

✓ **Dynamic inventory** - Auto-discovery of EC2 instances  
✓ **Intelligent grouping** - Environment and Role-based groups  
✓ **Secure connections** - SSM without SSH  
✓ **Variable hierarchy** - Flexible configuration management  
✓ **Performance** - Inventory caching  
✓ **Safety** - --limit patterns for accident prevention  
✓ **Scalability** - Works from 10 to 10,000+ instances  
✓ **Compliance** - Session logging and audit trails  

Ready for production use!
