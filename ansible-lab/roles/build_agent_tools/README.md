# Build Agent Tools Role

Installs required build tools on GitHub Actions self-hosted runners: Docker, Kubernetes tools (kubectl, Helm), AWS CLI v2, .NET SDK, Maven, Node.js, and Python.

## Features

- **Modular Subtasks**: Each tool installed via separate included task file (can be customized/reused)
- **Conditional Installation**: Enable/disable each tool via flags
- **Block/Rescue/Always**: Graceful error handling per tool (partial success if some fail)
- **Idempotent**: Skip tool installation if already at target version
- **OS Detection**: Supports Ubuntu, Debian, and Amazon Linux with OS-specific package managers
- **Fact-Based Conditionals**: Uses `ansible_facts` to detect OS family and distribution
- **User/Directory Setup**: Creates runner user and working directories

## Supported Operating Systems

- Ubuntu 22.04 LTS, 24.04
- Debian 11, 12
- Amazon Linux 2, 2023

## Tools Installed

| Tool | Version | Purpose |
|------|---------|---------|
| Docker CE | Latest | Container runtime |
| kubectl | v1.27.0 | Kubernetes CLI |
| Helm | v3.12.0 | Kubernetes package manager |
| AWS CLI | v2 | AWS cloud CLI |
| .NET SDK | 7.0 | .NET development |
| Maven | 3.9.2 | Java build tool |
| Node.js | v18.17.0 | JavaScript runtime |
| Python | 3.x + pip | Python runtime |

## Variables

### Installation Flags
- `install_docker: true` - Install Docker CE
- `install_kubernetes_tools: true` - Install kubectl and Helm
- `install_aws_cli: true` - Install AWS CLI v2
- `install_build_tools: true` - Install .NET, Maven, Node.js, Python

### Runner Configuration
- `runner_username: github-runner` - Non-root user for runner
- `runner_home: /home/github-runner` - Home directory
- `runner_work_dir: /home/github-runner/_work` - Working directory for jobs

### Tool Versions
- `kubectl_version: v1.27.0`
- `helm_version: v3.12.0`
- `maven_version: 3.9.2`
- `dotnet_version: 7.0`
- `nodejs_version: v18.17.0`

## Usage Example

```yaml
---
- name: Install build tools on runner
  hosts: github_runners
  become: true
  vars:
    runner_username: github-runner
    install_docker: true
    install_kubernetes_tools: true
    install_aws_cli: true
    install_build_tools: true
  roles:
    - build_agent_tools
```

### Selective Installation

```yaml
---
- name: Install only Docker and Python
  hosts: github_runners
  become: true
  vars:
    install_docker: true
    install_kubernetes_tools: false
    install_aws_cli: false
    install_build_tools: true  # Installs .NET, Maven, Node, Python
  roles:
    - build_agent_tools
```

## How It Works

1. **Gather Facts** - Collects system information (OS, distribution, memory, etc.)
2. **Assert OS** - Validates operating system is supported
3. **Setup Prerequisites** - Updates package manager, installs base utilities (git, curl, unzip, jq)
4. **Create Runner User** - Creates non-root `github-runner` user and working directories
5. **Conditional Tool Installation**:
   - Each tool installed in separate included task file
   - Block/Rescue/Always pattern: attempt install → log failure → continue with next tool
   - Version checks: skip reinstall if already installed
6. **Validation** - Displays version of each successfully installed tool

## Error Handling

Each tool installation uses **block/rescue/always**:

- **Block**: Installs tool (download → extract → install → configure)
- **Rescue**: Logs failure without stopping playbook (graceful degradation)
- **Always**: Displays status summary

Example:
```yaml
block:
  - Download tool
  - Install tool
  - Validate installation
rescue:
  - Log error message
  - Continue with next tool
always:
  - Display summary
```

This allows partial success: if Helm fails to install, Docker and other tools still complete.

## OS-Specific Behavior

### Debian/Ubuntu
- Uses `apt` package manager
- Docker installed from official Docker repository
- .NET SDK via Microsoft package repository

### RedHat/Amazon Linux
- Uses `yum` package manager
- Docker installed from Docker repository (via yum-config-manager)
- .NET SDK via Microsoft package repository

## Idempotency

The role is idempotent and can be safely re-run:
- Tool version checks skip reinstallation if already installed
- Directory creation skips if already exists
- User creation skips if already exists
- System packages checked before installation

## Performance Considerations

- **First Run**: 15-20 minutes (downloads all tools, ~2-3 GB disk space)
- **Subsequent Runs**: 1-2 minutes (version checks only, skips installation)
- **Resource Requirements**: 
  - Disk: 4 GB free (minimum 6 GB recommended)
  - Memory: 2 GB (4 GB recommended)
  - CPU: 2 vCPU (4 vCPU recommended)
  - Network: Requires internet access (or internal mirrors configured)

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Docker installation fails | Repository access issue | Check internet connectivity, verify Docker repo URLs |
| kubectl download timeout | Network issue | Retry playbook or configure internal mirror |
| .NET SDK not found | Wrong Ubuntu version | Verify Ubuntu 22.04 or update dotnet_version |
| Maven PATH not available | Profile not sourced in shell | Source `/etc/profile.d/maven.sh` in shell |
| Permission denied on tool installation | Insufficient permissions | Ensure playbook runs with `become: true` |
| Disk space full | Too many tools installed | Check `/opt` and `/usr/local` directories |

## Tags

- `build_agent_tools`: All tasks
- `prerequisites`: Package manager updates and base utilities
- `docker`: Docker CE installation
- `kubernetes`: kubectl and Helm installation
- `aws`: AWS CLI v2 installation
- `build-tools`: .NET, Maven, Node.js, Python installation
- `validation`: Tool version verification
- `summary`: Installation summary display

Example: Run only Docker installation:
```bash
ansible-playbook playbooks/provision-github-runner.yaml -t docker
```

## Dependencies

- `ansible.builtin` collection
- Internet access to download tools (or configure internal mirrors in `vars/main.yml`)
- `become: true` privileges for system package installation

## Notes

- Runner user is created with home directory `/home/github-runner`
- Runner user is added to `docker` group for Docker access without `sudo`
- All tools installed to system paths for global availability
- Each tool can be individually enabled/disabled via role variables
- Subtask files can be included separately in other roles if needed
