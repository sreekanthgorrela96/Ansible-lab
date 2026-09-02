# GitHub Runner Role

Registers and manages GitHub Actions self-hosted runners on a target host. Handles secure GitHub PAT token management with `no_log`, downloads latest runner release, configures systemd service, and provides graceful deregistration.

## Features

- **Secure Token Handling**: GitHub PAT token wrapped with `no_log: true` (never logged or exposed)
- **Automatic Release Discovery**: Fetches latest GitHub Actions Runner release from GitHub API
- **Idempotent Registration**: Skips re-registration if runner already configured
- **Systemd Service Management**: Creates systemd unit file with auto-restart
- **Block/Rescue/Always**: Comprehensive error handling with actionable troubleshooting
- **Graceful Deregistration**: Separate deregister.yml task for clean teardown
- **Service Validation**: Confirms runner service is running post-registration

## Prerequisites

- Host must have Docker and other build tools installed (via `build_agent_tools` role)
- GitHub Personal Access Token (PAT) with required scopes
- Network access to GitHub API (github.com or GitHub Enterprise instance)
- Sudo/become privileges for systemd service configuration

## Required Variables

These **MUST** be provided at runtime (via inventory, playbook vars, or vault):

```yaml
github_pat_token: "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"  # GitHub PAT
github_repo_url: "https://github.com/myorg/myrepo"  # Repository URL
```

## GitHub Personal Access Token (PAT)

### Creating a PAT

1. Go to GitHub Settings > Developer settings > Personal access tokens > Tokens (classic)
2. Click "Generate new token (classic)"
3. **Scopes Required**:
   - `repo` - Full control of private repositories
   - `admin:org_hook` - Write access to organization webhooks
   - `workflow` - Update GitHub Actions workflows
4. Copy token (shown once)
5. Store securely in Ansible vault

### Token Security Best Practices

- **Never commit PAT to git** (always use vault or environment variables)
- **Restrict token scope** to minimum required permissions
- **Rotate tokens regularly** (GitHub recommends every 90 days)
- **Use `no_log: true`** in tasks (this role does this automatically)
- **Store in Ansible vault** with restricted file permissions

## Variables

### Required
- `github_pat_token` - Personal Access Token
- `github_repo_url` - Repository URL

### Optional
- `runner_name` - Display name in GitHub UI (default: `{{ inventory_hostname }}-runner`)
- `runner_labels` - Job targeting labels (default: `[self-hosted, linux, x64, docker, aws]`)
- `runner_username` - Non-root user (default: `github-runner`)
- `runner_work_dir` - Installation path (default: `/home/github-runner/runner`)
- `runner_group` - Runner group name (default: `default`)
- `runner_owner` - Owner/team identifier (default: `DevOps`)
- `runner_environment` - Environment tag (default: `production`)

## Usage Example

### Basic Registration

```yaml
---
- name: Register GitHub Actions runner
  hosts: github_runners
  become: true
  vars:
    github_pat_token: "{{ vault_github_pat_token }}"
    github_repo_url: "https://github.com/myorg/myrepo"
  roles:
    - github_runner
```

### With Custom Labels and Runner Name

```yaml
---
- name: Register GitHub Actions runner
  hosts: ec2_instances
  become: true
  vars:
    github_pat_token: "{{ vault_github_pat_token }}"
    github_repo_url: "https://github.com/myorg/myrepo"
    runner_name: "prod-runner-{{ ansible_hostname }}"
    runner_labels:
      - self-hosted
      - linux
      - x64
      - docker
      - aws
      - production
  roles:
    - github_runner
```

### Using Vault for PAT

```bash
# Store PAT in vault
ansible-vault create inventory/group_vars/github_runners/vault.yml

# Content:
# vault_github_pat_token: "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

Then in playbook:
```yaml
---
- name: Register runner
  hosts: github_runners
  become: true
  vars:
    github_pat_token: "{{ vault_github_pat_token }}"
    github_repo_url: "https://github.com/myorg/myrepo"
  roles:
    - github_runner
```

### Full Provisioning Playbook

```yaml
---
- name: Provision GitHub Actions runner
  hosts: localhost
  connection: local
  gather_facts: true
  roles:
    - ec2_buildagent

- name: Configure GitHub Actions runner
  hosts: "{{ ec2_instance.instances[0].public_ip_address }}"
  become: true
  gather_facts: true
  vars:
    github_pat_token: "{{ vault_github_pat_token }}"
    github_repo_url: "https://github.com/myorg/myrepo"
  roles:
    - build_agent_tools
    - github_runner
```

## How It Works

1. **Discover Runner Version** - Queries GitHub API to get latest Actions Runner release
2. **Download Runner** - Downloads runner tarball from GitHub releases
3. **Extract Runner** - Extracts runner to working directory
4. **Create Environment File** - Creates `.env` file with PAT and configuration (mode 0600)
5. **Register with GitHub** - Runs `config.sh` to register runner (PAT protected with `no_log`)
6. **Create Service File** - Generates systemd unit file from template
7. **Enable Service** - Enables and starts systemd service with auto-restart
8. **Validate** - Confirms service is running

## Deregistration (Cleanup)

To cleanly deregister runner from GitHub and remove local files:

```yaml
---
- name: Deregister and cleanup GitHub runner
  hosts: github_runners
  become: true
  tasks:
    - name: Include deregister task
      ansible.builtin.include_tasks: roles/github_runner/tasks/deregister.yml
```

Or as a separate playbook:

```yaml
---
- name: Teardown GitHub runner
  hosts: github_runners
  become: true
  vars:
    github_pat_token: "{{ vault_github_pat_token }}"
  tasks:
    - name: Deregister runner
      ansible.builtin.include_tasks: roles/github_runner/tasks/deregister.yml
```

The deregister task:
- Stops the systemd service
- Runs `config.sh remove` with PAT token
- Removes systemd service file
- Deletes runner directory
- Removes runner user

## Verifying Runner Registration

### In GitHub UI

1. Navigate to repository: Settings > Actions > Runners
2. Verify runner appears with status "Idle" or "Active"
3. Runner name should match `runner_name` variable
4. Labels should include values from `runner_labels`

### In Repository Workflow

Add a test workflow targeting the runner:

```yaml
name: Test Self-Hosted Runner
on: [push]
jobs:
  test:
    runs-on: [self-hosted, linux]
    steps:
      - run: echo "Running on self-hosted runner"
      - run: docker --version
      - run: kubectl version --client
      - run: aws --version
      - run: dotnet --version
      - run: mvn --version
      - run: node --version
      - run: python3 --version
```

### Via systemd

```bash
# Check service status
systemctl status github-runner

# View logs
journalctl -u github-runner -f

# Restart service
systemctl restart github-runner
```

## Error Handling

The role uses **block/rescue/always** pattern:

- **Block**: Attempts runner download, extraction, registration, and service setup
- **Rescue**: Logs error details (without exposing PAT) and fails with troubleshooting steps
- **Always**: Displays setup summary with verification instructions

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `GitHub API rate limit exceeded` | Too many API requests | Wait or use GitHub Enterprise with higher rate limits |
| `Invalid authentication credentials` | Wrong PAT or expired token | Verify PAT in vault, regenerate if needed |
| `Repository not found` | Incorrect repo URL | Verify URL format: `https://github.com/org/repo` |
| `runner already exists` | Runner name collision | Use unique runner_name or delete existing runner |
| `Service failed to start` | Missing dependencies | Ensure `build_agent_tools` role ran successfully |
| `Download timeout` | Network issue | Check internet connectivity, retry playbook |

## Security Considerations

- **PAT Scope**: Limit PAT to minimum required permissions
- **Token Rotation**: Rotate tokens every 90 days
- **Environment File**: `.env` file created with mode `0600` (owner-only readable)
- **no_log Protection**: All tasks using PAT wrapped with `no_log: true`
- **Service Sandboxing**: Systemd service uses `PrivateTmp`, `ProtectHome`, `NoNewPrivileges`
- **Audit Logging**: Service output logged to journal (queryable via `journalctl`)

## Performance

- **First Registration**: 2-5 minutes (download + extract + register)
- **Idempotent Re-runs**: < 30 seconds (skips if already configured)
- **Service Startup**: 5-10 seconds post-reboot
- **API Timeout**: 30 seconds per GitHub API call

## Dependencies

- Requires `build_agent_tools` role (for git, curl, Docker)
- Requires internet access to GitHub API
- Requires `become: true` privileges for systemd operations

## Tags

- `github_runner`: All tasks
- `download`: Runner download task
- `registration`: Registration tasks
- `service`: Systemd service configuration
- `validation`: Service verification
- `error`: Error handling
- `summary`: Summary display
- `deregister`: Deregistration tasks (in deregister.yml)

Example: Run only service configuration:
```bash
ansible-playbook playbooks/provision-github-runner.yaml -t service
```

## Notes

- Idempotency: Runner registration checked via `runner-config` marker file
- Auto-restart: Systemd service has `Restart=always` with 15-second delay
- Multi-runner: This role provisions one runner per host; use in loop for multiple
- GitHub Enterprise: Adjust `github_api_url` and `runner_releases_url` for GHE instances
