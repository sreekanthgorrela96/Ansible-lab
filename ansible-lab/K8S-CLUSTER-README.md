# Kubernetes Cluster Setup (Ubuntu 26.04)

Ansible playbook and roles that build a kubeadm cluster with containerd and Calico. The flow follows the Ubuntu kubeadm tutorial, with the command and CNI mistakes from that PDF corrected.

## What this creates

```
k8s-cluster.yaml
├── k8s_node            # every node: swap off, sysctl, containerd, kubeadm/kubelet/kubectl
├── k8s_control_plane   # kubeadm init --pod-network-cidr, Calico, join token, kubeconfig fetch
├── k8s_worker          # kubeadm join using the live token from the control plane
└── verify              # kubectl get nodes / pods -A
```

Fixes versus the original PDF:

- Valid `gpg --dearmor`, `sudo tee`, and `sed` usage
- Docker and Kubernetes apt keys in `/etc/apt/keyrings` with `signed-by`
- containerd `SystemdCgroup = true` and a pause image that matches kubeadm
- `kubeadm init --pod-network-cidr=192.168.0.0/16` before Calico
- Live `kubeadm token create --print-join-command` (no copied sample token/hash)
- Kubernetes 1.33 from `pkgs.k8s.io` (1.29 in the PDF is end-of-life)
- Calico v3.28.2 instead of v3.25.0
- kubelet enabled; cluster verified with nodes and kube-system pods

## Prerequisites

On the Ansible controller:

- Ansible 2.14+
- Collections from `collections/requirements.yml` (`ansible.posix`, `community.general`)

```bash
ansible-galaxy collection install -r collections/requirements.yml
```

On every cluster node:

- Ubuntu 26.04
- SSH access and passwordless (or become) sudo
- Unique hostname (the role sets hostname to `inventory_hostname`)
- Control plane: at least 2 CPUs and 2 GiB RAM
- Full L3 connectivity between nodes
- Pod CIDR `192.168.0.0/16` must **not** overlap your LAN. If your lab is already on 192.168.0.0/16, change `k8s_pod_network_cidr` in inventory before you run.

Required ports (open them, or set `k8s_configure_ufw: true` if UFW is active):

| Port | Use |
|---|---|
| 6443/tcp | Kubernetes API |
| 2379-2380/tcp | etcd (control plane) |
| 10250/tcp | kubelet |
| 10257/tcp, 10259/tcp | controller-manager / scheduler |
| 179/tcp | Calico BGP |
| 4789/udp | Calico VXLAN |
| 30000-32767/tcp | NodePorts |

## 1. Edit inventory

File: `ansible-lab/inventory/k8s/hosts`

```ini
[k8s_control_plane]
k8s-master ansible_host=192.168.34.10 ansible_user=sgorrela

[k8s_workers]
k8s-worker1 ansible_host=192.168.34.236 ansible_user=sgorrela
```

- Put the real control-plane IP on `k8s-master`.
- Do **not** list the control-plane host under `[k8s_workers]`.
- For a single-node lab, leave `[k8s_workers]` empty and set `k8s_allow_control_plane_workloads: true` in `ansible-lab/inventory/k8s/group_vars/all.yml`.

Cluster settings live in `ansible-lab/inventory/k8s/group_vars/all.yml`. That inventory uses SSH + sudo on purpose so it does not inherit the AWS SSM defaults used by the dynamic inventory.

## 2. Check connectivity

From the repo root:

```bash
ansible k8s_cluster -i ansible-lab/inventory/k8s/hosts -m ping
```

If sudo needs a password:

```bash
ansible k8s_cluster -i ansible-lab/inventory/k8s/hosts -m ping --ask-become-pass
```

## 3. Run the cluster playbook

```bash
ansible-playbook -i ansible-lab/inventory/k8s/hosts ansible-lab/playbooks/k8s-cluster.yaml
```

Dry-run (check mode cannot fully simulate `kubeadm init`/`join`):

```bash
ansible-playbook -i ansible-lab/inventory/k8s/hosts ansible-lab/playbooks/k8s-cluster.yaml --check --diff
```

Useful tags:

```bash
# Node prep only (containerd + kubeadm packages)
ansible-playbook -i ansible-lab/inventory/k8s/hosts ansible-lab/playbooks/k8s-cluster.yaml --tags node

# Control plane only (after nodes are prepared)
ansible-playbook -i ansible-lab/inventory/k8s/hosts ansible-lab/playbooks/k8s-cluster.yaml --tags control_plane,verify

# Join additional workers later (control plane play still runs to mint a join token)
ansible-playbook -i ansible-lab/inventory/k8s/hosts ansible-lab/playbooks/k8s-cluster.yaml --tags control_plane,worker,verify
```

The playbook is idempotent enough to re-run: `kubeadm init` and `kubeadm join` are skipped when `/etc/kubernetes/admin.conf` or `/etc/kubernetes/kubelet.conf` already exist.

## 4. Use the cluster

On the control plane:

```bash
kubectl get nodes
kubectl get pods -A
```

The role also copies kubeconfig to `/home/<ansible_user>/.kube/config` and, by default, fetches it to:

`ansible-lab/kubeconfig/<control-plane-hostname>.conf`

From the controller:

```bash
export KUBECONFIG=ansible-lab/kubeconfig/k8s-master.conf
kubectl get nodes
```

## Variables

Override in `inventory/k8s/group_vars/all.yml` or with `-e`.

| Variable | Default | Purpose |
|---|---|---|
| `k8s_minor_version` | `1.33` | `pkgs.k8s.io` channel (`v1.33`, `v1.34`, …) |
| `k8s_pause_image` | `registry.k8s.io/pause:3.10` | containerd sandbox image |
| `k8s_pod_network_cidr` | `192.168.0.0/16` | Must match Calico |
| `k8s_service_cidr` | `10.96.0.0/12` | ClusterIP range |
| `k8s_cni_manifest_url` | Calico v3.28.2 manifest | CNI install URL |
| `k8s_allow_control_plane_workloads` | `false` | Untaint control plane for single-node labs |
| `k8s_configure_ufw` | `false` | Open cluster ports if UFW is active |
| `k8s_fetch_kubeconfig` | `true` | Copy admin.conf back to the controller |
| `k8s_join_command` | *(from control plane)* | Optional extra-var if you join workers in a later run |

Example: newer Kubernetes channel

```bash
ansible-playbook -i ansible-lab/inventory/k8s/hosts ansible-lab/playbooks/k8s-cluster.yaml \
  -e k8s_minor_version=1.34
```

All nodes must use the same `k8s_minor_version`. Re-running after a channel change will not upgrade an existing cluster (packages are on `apt-mark hold`).

## Semaphore UI

Template type: Ansible playbook.

| Field | Value |
|---|---|
| Playbook | `ansible-lab/playbooks/k8s-cluster.yaml` |
| Inventory | `ansible-lab/inventory/k8s/hosts` (or a Semaphore static inventory with the same groups) |
| Extra args | `-e ansible_connection=ssh -e ansible_become=true -e ansible_become_user=root` |

Use a dry-run / check-mode prompt only for the node-prep tags. Do not expect `--check` to initialize a cluster.

## Tear down a node

This playbook does not destroy the cluster. On a node you want to remove:

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet
```

Then delete the node object from the control plane: `kubectl delete node <name>`.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `gpg: invalid option --dearmour` | Old docs; this role uses `--dearmor` |
| Nodes stay `NotReady` | CNI not ready, or pod CIDR overlaps the LAN |
| CoreDNS `CrashLoopBackOff` | Same CNI/CIDR issue; `kubectl get pods -A` |
| `connection plugin aws_ssm` | You used the AWS inventory; use `-i ansible-lab/inventory/k8s/hosts` |
| `Permission denied` creating system files | become is off; this inventory sets `ansible_become: true` |
| Worker join token invalid | Token expired (TTL 2h); re-run with `--tags control_plane,worker` |
| `kubeadm init` pause image warning | Role sets `sandbox_image`; flush/restart containerd happened before init |

## Role layout

```
ansible-lab/
├── playbooks/k8s-cluster.yaml
├── inventory/k8s/hosts
├── inventory/k8s/group_vars/all.yml
├── kubeconfig/                 # fetched admin.conf (gitignored)
└── roles/
    ├── k8s_node/
    ├── k8s_control_plane/
    └── k8s_worker/
```
