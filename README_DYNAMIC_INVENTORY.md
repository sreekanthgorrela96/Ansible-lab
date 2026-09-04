# AWS Dynamic Inventory with SSM Connection - Ansible Lab

## 📋 Overview

This Ansible lab demonstrates a **production-ready AWS dynamic inventory setup** featuring:

- ✅ **Dynamic Discovery** - Automatic EC2 instance discovery using `amazon.aws.aws_ec2` plugin
- ✅ **Intelligent Grouping** - Automatic group creation via `keyed_groups` on AWS tags:
  - `Environment` tags → `env_dev`, `env_qa`, `env_uat`, `env_stg`, `env_prod` groups
  - `Role` tags → `role_webserver`, `role_database`, `role_loadbalancer` groups
  - `Name` tags → Instance name-based groups
- ✅ **Secure Connections** - No SSH exposed! Uses `community.aws.aws_ssm` connection plugin
- ✅ **Group Variables Hierarchy** - Environment and role-specific configurations
- ✅ **Performance Optimized** - Inventory caching with 3600+ second TTL
- ✅ **Safety Features** - `--limit` patterns for accident-proof deployments
- ✅ **Production-Ready** - Compliance, audit logging, and change management

## 🚀 Quick Start (5 Minutes)

### 1. Install Collections
```bash
ansible-galaxy collection install -r ansible-lab/requirements.yaml
pip install -r requirements-python.txt
```

### 2. Configure AWS Credentials
```bash
aws configure
# Or set environment variables:
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_DEFAULT_REGION="us-east-1"
```

### 3. Create EC2 Instances with Tags
```bash
# Create dev webservers
ansible-playbook ansible-lab/playbooks/create-ec2-tagged.yaml \
  -e "environment=dev" \
  -e "instance_role=webserver" \
  -e "instance_count=2"
```

### 4. View Dynamic Inventory
```bash
# Show all groups
ansible-inventory -i ansible-lab/inventory/aws_ec2.yaml --graph

# Show specific hosts
ansible-inventory -i ansible-lab/inventory/aws_ec2.yaml --limit env_dev --list
```

### 5. Run Demo Playbook
```bash
ansible-playbook ansible-lab/playbooks/demo-dynamic-inventory.yaml \
  -i ansible-lab/inventory/aws_ec2.yaml \
  --limit env_dev
```

## 📁 File Structure

```
Ansible-lab/
├── ansible.cfg                          # Ansible configuration with cache settings
├── requirements-python.txt              # Python package requirements (boto3, etc.)
│
├── ansible-lab/
│   ├── inventory/
│   │   ├── aws_ec2.yaml                # Dynamic inventory plugin configuration
│   │   └── group_vars/
│   │       ├── all.yml                 # Global: SSM connection plugin
│   │       ├── env_dev.yml             # Development environment variables
│   │       ├── env_qa.yml              # QA environment variables
│   │       ├── env_uat.yml             # UAT environment variables
│   │       ├── env_stg.yml             # Staging environment variables
│   │       ├── env_prod.yml            # Production environment (strict)
│   │       ├── role_webserver.yml      # Webserver role variables
│   │       ├── role_database.yml       # Database role variables
│   │       └── role_loadbalancer.yml   # Load balancer role variables
│   │
│   ├── playbooks/
│   │   ├── demo-dynamic-inventory.yaml # Complete demonstration playbook
│   │   └── create-ec2-tagged.yaml      # Create tagged EC2 instances
│   │
│   └── requirements.yaml                # Ansible collections requirements
│
└── docs/
    ├── AWS_DYNAMIC_INVENTORY_GUIDE.md  # Complete reference guide
    └── QUICK_START_DYNAMIC_INVENTORY.md # Quick start commands
```

## 🔑 Key Components

### 1. Dynamic Inventory Plugin (`inventory/aws_ec2.yaml`)

Discovers EC2 instances and automatically creates groups based on tags:

```yaml
plugin: amazon.aws.aws_ec2
regions: [us-east-1, us-west-2]
compose:
  ansible_host: private_ip_address    # Use private IP for SSM
keyed_groups:
  - key: ec2_tags.Environment
    prefix: env
```

**Result**: Instances tagged with `Environment=dev` automatically joined to `env_dev` group

### 2. Group Variables Hierarchy

Variables applied in precedence order:

```
all.yml                    (SSM connection, common settings)
  ↓
env_dev.yml               (Environment-specific: timeouts, logging)
  ↓
role_webserver.yml        (Role-specific: ports, services)
  ↓
host_vars/hostname.yml    (Host-specific overrides)
```

### 3. SSM Connection Plugin (`group_vars/all.yml`)

```yaml
ansible_connection: community.aws.aws_ssm
ansible_aws_ssm_region: us-east-1
```

**Benefits**:
- No SSH keys needed
- No port 22 exposure
- IAM-based authentication
- Session logging for compliance
- Works across VPCs

### 4. Inventory Caching (`ansible.cfg`)

```ini
[aws_ec2]
cache = True
cache_plugin = jsonfile
cache_timeout = 3600
```

**Benefits**:
- First run: ~10 seconds (API call)
- Subsequent runs: <100ms (cached)
- Reduces AWS API calls by 90%+

## 📊 Example Grouping

### EC2 Instances
```
web01: Environment=dev, Role=webserver
web02: Environment=prod, Role=webserver
db01: Environment=prod, Role=database
lb01: Environment=stg, Role=loadbalancer
```

### Generated Groups
```
env_dev:           [web01]
env_prod:          [web02, db01]
env_stg:           [lb01]
role_webserver:    [web01, web02]
role_database:     [db01]
role_loadbalancer: [lb01]
environments:      [env_dev, env_prod, env_stg]
roles:             [role_webserver, role_database, role_loadbalancer]
```

## 🛡️ Safe Limit Patterns

### Pattern 1: Environment Only (Safest)
```bash
ansible-playbook site.yml --limit env_dev      # All dev hosts
ansible-playbook site.yml --limit env_prod     # All prod hosts
```

### Pattern 2: Environment + Role (Specific)
```bash
# Only production webservers
ansible-playbook site.yml --limit "env_prod:&role_webserver"

# Only dev databases
ansible-playbook site.yml --limit "env_dev:&role_database"
```

### Pattern 3: Exclude Production (Safety)
```bash
# Everything except production (safe test)
ansible-playbook site.yml --limit "all:!env_prod"
```

### Pattern 4: Multiple Environments (Controlled)
```bash
# Dev and QA together (no production)
ansible-playbook site.yml --limit "env_dev,env_qa"
```

## 📖 Configuration Examples

### Development Environment (`env_dev.yml`)
```yaml
environment_name: development
ansible_connection_timeout: 30
log_level: DEBUG
enable_performance_logging: true
fallback_ssh_enabled: true        # SSH allowed if SSM fails
security_scanning_enabled: false
```

### Production Environment (`env_prod.yml`)
```yaml
environment_name: production
ansible_connection_timeout: 90
require_approval_for_changes: true
ansible_become: true
enable_ssl: true
backup_retention_days: 30
compliance_checking: true
fallback_ssh_enabled: false       # SSM-only, no SSH
```

### Webserver Role (`role_webserver.yml`)
```yaml
role_name: webserver
http_port: 80
https_port: 443
webserver_service: nginx
enable_ssl: true
enable_http2: true
enable_rate_limiting: true
```

## 🔗 Common Commands

```bash
# View inventory structure
ansible-inventory -i ansible-lab/inventory/aws_ec2.yaml --graph

# List all production hosts
ansible-inventory -i ansible-lab/inventory/aws_ec2.yaml --limit env_prod --list

# List production webservers only
ansible-inventory -i ansible-lab/inventory/aws_ec2.yaml --limit "env_prod:&role_webserver" --list

# Run playbook on dev environment
ansible-playbook ansible-lab/playbooks/demo-dynamic-inventory.yaml \
  -i ansible-lab/inventory/aws_ec2.yaml \
  --limit env_dev

# Run on production with safety confirmation
ansible-playbook ansible-lab/playbooks/demo-dynamic-inventory.yaml \
  -i ansible-lab/inventory/aws_ec2.yaml \
  --limit env_prod \
  -e "i_understand_this_is_production=true"

# Refresh inventory cache
ansible-inventory -i ansible-lab/inventory/aws_ec2.yaml --force-cache

# Test SSM connection to specific host
ansible all -i ansible-lab/inventory/aws_ec2.yaml -m ping --limit prod-webserver-01
```

## 🔐 Prerequisites

### AWS Permissions
Your AWS user/role needs:
- `ec2:DescribeInstances`
- `ec2:DescribeTags`
- `ssm:StartSession`
- `ssm:TerminateSession`
- `ec2messages:GetMessages`

See: [`docs/AWS_DYNAMIC_INVENTORY_GUIDE.md`](docs/AWS_DYNAMIC_INVENTORY_GUIDE.md#prerequisites) for complete IAM policy

### EC2 Instance Setup
1. **IAM Role**: Attach `AmazonSSMManagedInstanceCore` policy
2. **SSM Agent**: Pre-installed on Amazon Linux 2, Ubuntu 16.04+
3. **Security Group**: Allow HTTPS (443) for SSM
4. **Tags**: Must include `Environment` and `Role` tags

## 📚 Documentation

- **[AWS_DYNAMIC_INVENTORY_GUIDE.md](docs/AWS_DYNAMIC_INVENTORY_GUIDE.md)** - Complete reference guide
  - Architecture overview
  - Configuration details
  - Usage examples
  - Troubleshooting
  - Best practices

- **[QUICK_START_DYNAMIC_INVENTORY.md](docs/QUICK_START_DYNAMIC_INVENTORY.md)** - Quick reference
  - One-line commands
  - Common patterns
  - Performance tips
  - Debugging steps

- **[demo-dynamic-inventory.yaml](ansible-lab/playbooks/demo-dynamic-inventory.yaml)** - Demonstration playbook
  - Shows how to use dynamic inventory
  - Demonstrates variable precedence
  - Shows SSM connection
  - Displays best practices

## 🎯 Common Use Cases

### Deploy to Development
```bash
ansible-playbook site.yml \
  -i ansible-lab/inventory/aws_ec2.yaml \
  --limit env_dev
```

### Deploy to All Webservers (Non-Prod)
```bash
ansible-playbook deploy-app.yml \
  -i ansible-lab/inventory/aws_ec2.yaml \
  --limit "all:&role_webserver:!env_prod"
```

### Patch All Databases
```bash
ansible-playbook patching/patch.yml \
  -i ansible-lab/inventory/aws_ec2.yaml \
  --limit "role_database" \
  --serial 1  # One at a time for HA
```

### Blue-Green Deployment
```bash
# Deploy to staging (pre-production)
ansible-playbook deploy.yml \
  -i ansible-lab/inventory/aws_ec2.yaml \
  --limit env_stg

# Verify in production
ansible-playbook verify.yml \
  -i ansible-lab/inventory/aws_ec2.yaml \
  --limit env_prod \
  --check

# Promote to production
ansible-playbook deploy.yml \
  -i ansible-lab/inventory/aws_ec2.yaml \
  --limit env_prod \
  -e "i_understand_this_is_production=true"
```

## 🐛 Troubleshooting

### Inventory Not Showing Hosts
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify EC2 instances are running
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"

# Check instance tags
aws ec2 describe-instances --query 'Reservations[*].Instances[*].Tags'

# Verify SSM Agent status
aws ssm describe-instance-information
```

### SSM Connection Fails
```bash
# Verify IAM instance role
aws ec2 describe-instances --instance-ids i-xxx --query 'Reservations[0].Instances[0].IamInstanceProfile'

# Check security group allows 443
aws ec2 describe-security-groups --group-ids sg-xxx

# Test SSM session
aws ssm start-session --target i-xxx
```

### Slow Inventory Loading
```bash
# Clear cache
rm -rf .ansible/cache/

# Check cache age
stat .ansible/cache/aws_ec2_*

# Verify cache is enabled in ansible.cfg
grep -A 5 "[aws_ec2]" ansible.cfg
```

## 📝 Notes

- **First Run**: Takes 10-30 seconds (API calls + caching)
- **Subsequent Runs**: <100ms (cached inventory)
- **Cache Timeout**: 3600 seconds (1 hour) - adjust in `ansible.cfg`
- **Regions**: Modify in `inventory/aws_ec2.yaml` to add/remove regions
- **Filters**: Add/modify filters in `inventory/aws_ec2.yaml` to exclude instances

## 🤝 Contributing

To add new features or improvements:

1. Test locally first: `--limit env_dev --check`
2. Document changes in relevant docs
3. Add examples to demo playbook
4. Update group_vars as needed

## 📄 License

MIT-0 (Same as Ansible Lab)

---

**Next Steps**: See [`docs/QUICK_START_DYNAMIC_INVENTORY.md`](docs/QUICK_START_DYNAMIC_INVENTORY.md) for detailed commands, or run the demo:

```bash
ansible-playbook ansible-lab/playbooks/demo-dynamic-inventory.yaml \
  -i ansible-lab/inventory/aws_ec2.yaml \
  --limit env_dev \
  -v
```
