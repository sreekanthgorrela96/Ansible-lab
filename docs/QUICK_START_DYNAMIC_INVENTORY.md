---
# AWS Dynamic Inventory Quick Start Guide
# 
# Get up and running with AWS dynamic inventory in 5 minutes

# 1. PREREQUISITES (One-time setup)

## 1.1 Install Collections
ansible-galaxy collection install amazon.aws community.aws
pip install boto3 botocore

## 1.2 Configure AWS Credentials
aws configure
# OR
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_DEFAULT_REGION="us-east-1"

## 1.3 Create IAM Role for EC2 Instances
# Create IAM role with policy: AmazonSSMManagedInstanceCore
# Attach to EC2 instances so SSM Agent can communicate

## 1.4 Verify SSM Agent on EC2 Instances
aws ssm describe-instance-information --query 'InstanceInformationList[*].{ID:InstanceIds, Ping:PingStatus}'

---

# 2. CREATE EC2 INSTANCES WITH TAGS

# Option A: Create instances with Ansible (see playbooks/create-ec2-tagged.yaml)
ansible-playbook playbooks/create-ec2-tagged.yaml \
  -e "environment=dev" \
  -e "instance_role=webserver" \
  -e "instance_count=2"

# Option B: Create manually with AWS CLI
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.medium \
  --key-name ansible-key \
  --security-group-ids sg-12345678 \
  --iam-instance-profile Arn=arn:aws:iam::123456789:instance-profile/EC2-SSM-InstanceProfile \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Environment,Value=dev},{Key=Role,Value=webserver},{Key=Name,Value=dev-webserver-01}]'

# Option C: Tag existing instances
aws ec2 create-tags \
  --resources i-1234567890abcdef0 \
  --tags Key=Environment,Value=dev Key=Role,Value=webserver Key=Name,Value=dev-webserver-01

---

# 3. VIEW DYNAMIC INVENTORY

# Show all groups created from tags
ansible-inventory -i inventory/aws_ec2.yaml --graph

# Show detailed inventory (includes host variables)
ansible-inventory -i inventory/aws_ec2.yaml --list | python -m json.tool

# Show inventory tree (requires ansible-inventory-tree plugin)
ansible-inventory -i inventory/aws_ec2.yaml --graph --inventory-file=<file>

---

# 4. RUN PLAYBOOKS WITH SAFE LIMITS

# DEVELOPMENT (safest - no production impact)
ansible-playbook playbooks/demo-dynamic-inventory.yaml \
  -i inventory/aws_ec2.yaml \
  --limit env_dev

# QA ENVIRONMENT
ansible-playbook playbooks/demo-dynamic-inventory.yaml \
  -i inventory/aws_ec2.yaml \
  --limit env_qa

# SPECIFIC ROLE IN ENVIRONMENT
ansible-playbook playbooks/demo-dynamic-inventory.yaml \
  -i inventory/aws_ec2.yaml \
  --limit "env_dev:&role_webserver"

# PRODUCTION (requires explicit confirmation)
ansible-playbook playbooks/demo-dynamic-inventory.yaml \
  -i inventory/aws_ec2.yaml \
  --limit env_prod \
  -e "i_understand_this_is_production=true"

---

# 5. TEST SSM CONNECTION

# List all instances with SSM connectivity
aws ssm describe-instance-information

# Start interactive session
aws ssm start-session --target i-1234567890abcdef0

# Run Ansible command against specific host
ansible all -i inventory/aws_ec2.yaml --limit dev-webserver-01 -m command -a "uptime"

---

# 6. VERIFY GROUP VARIABLES PRECEDENCE

# Show all variables for a specific host
ansible-inventory -i inventory/aws_ec2.yaml --host dev-webserver-01 | python -m json.tool

# Show groups for a host
ansible-inventory -i inventory/aws_ec2.yaml --host dev-webserver-01 | python -m json.tool | grep -A 10 '"group_names"'

# Check specific variable values
ansible all -i inventory/aws_ec2.yaml --limit dev-webserver-01 -m debug -a var=ansible_timeout

---

# 7. TROUBLESHOOTING COMMANDS

# Verify dynamic inventory file syntax
python -c "import yaml; yaml.safe_load(open('ansible-lab/inventory/aws_ec2.yaml'))"

# Test AWS connection
aws sts get-caller-identity

# Check EC2 instances
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[InstanceId,PrivateIpAddress,Tags[?Key==`Name`].Value|[0]]'

# Check tags on instances
aws ec2 describe-instances --query 'Reservations[*].Instances[*].Tags'

# Verify SSM Agent status
aws ssm send-command \
  --instance-ids i-1234567890abcdef0 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["systemctl status amazon-ssm-agent"]'

# Check IAM permissions for SSM
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789:user/ansible-user \
  --action-names ssm:StartSession ec2:DescribeInstances \
  --resource-arns "*"

# Force inventory cache refresh
ansible-inventory -i inventory/aws_ec2.yaml --force-cache

# View inventory cache
ls -la .ansible/cache/

---

# 8. COMMON PATTERNS

# All hosts in development
--limit env_dev

# All webservers in all environments
--limit "all:&role_webserver"

# Production webservers and databases
--limit "env_prod:&(role_webserver|role_database)"

# All except production (safety pattern)
--limit "all:!env_prod"

# Multiple specific environments
--limit "env_dev,env_qa"

# By name pattern (if using tag_Name groups)
--limit "tag_Name_*webserver*"

---

# 9. PERFORMANCE OPTIMIZATION

# Check cache status
ls -la .ansible/cache/ | grep aws_ec2

# Clear cache completely
rm -rf .ansible/cache/aws_ec2_*

# Force cache refresh (useful in CI/CD)
ansible-inventory -i inventory/aws_ec2.yaml --force-cache --list > /dev/null

# Cache refresh with cron (add to crontab)
0 * * * * cd /path/to/ansible && ansible-inventory -i inventory/aws_ec2.yaml --force-cache

---

# 10. PRODUCTION DEPLOYMENT WORKFLOW

# Step 1: Test in development
ansible-playbook playbooks/site.yaml -i inventory/aws_ec2.yaml --limit env_dev -v

# Step 2: Validation check
ansible-playbook playbooks/site.yaml -i inventory/aws_ec2.yaml --limit env_dev --check

# Step 3: Deploy to QA
ansible-playbook playbooks/site.yaml -i inventory/aws_ec2.yaml --limit env_qa -v

# Step 4: Deploy to production (with confirmation)
ansible-playbook playbooks/site.yaml \
  -i inventory/aws_ec2.yaml \
  --limit env_prod \
  -e "i_understand_this_is_production=true" \
  --ask-become-pass

---

# TIPS & TRICKS

# Get count of hosts per environment
ansible-inventory -i inventory/aws_ec2.yaml --graph | grep "env_" | wc -l

# Get specific environment host count
ansible-inventory -i inventory/aws_ec2.yaml --limit env_prod --list | grep -c '"ansible_host"'

# List all available groups
ansible-inventory -i inventory/aws_ec2.yaml --graph | grep "@" | sed 's/.*@//'

# Show hosts by role
ansible-inventory -i inventory/aws_ec2.yaml --graph | grep -A 100 "@role_webserver"

# Export inventory to JSON for processing
ansible-inventory -i inventory/aws_ec2.yaml --list > inventory.json

# Monitor inventory changes
watch -n 60 "ansible-inventory -i inventory/aws_ec2.yaml --graph"

---

# DOCUMENTATION

Full guide available in:
docs/AWS_DYNAMIC_INVENTORY_GUIDE.md

Demo playbook with detailed examples:
playbooks/demo-dynamic-inventory.yaml

EC2 creation playbook:
playbooks/create-ec2-tagged.yaml

---
