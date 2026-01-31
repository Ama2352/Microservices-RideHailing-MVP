# Platform Setup Guide: Istio & Jenkins

This guide explains the newly added platform components and how to deploy them on your local Kubernetes cluster.

---

## Directory Structure

```
infrastructure/vm/platform/
├── istio/
│   ├── install-istio.sh      # Installs Istio with minimal profile
│   └── uninstall-istio.sh    # Removes Istio completely
│
└── jenkins/
    ├── .env                   # Environment variables (admin password)
    ├── 00-namespace.yaml      # Jenkins namespace
    ├── 01-rbac.yaml           # ServiceAccount & RBAC permissions
    ├── 02-storage.yaml        # PersistentVolume & PVC (HostPath)
    ├── 03-deployment.yaml     # Jenkins Deployment (resource-limited)
    ├── 04-service.yaml        # NodePort Service
    ├── install-jenkins.sh     # One-command installation
    └── uninstall-jenkins.sh   # Clean removal
```

---

## Prerequisites

Before deploying, ensure your Kubernetes cluster is running:

```bash
# SSH into the master node
vagrant ssh k8s-master

# Verify cluster status
kubectl get nodes
```

All nodes should be in `Ready` state.

---

## Joining Worker Nodes to the Cluster

After the master node is initialized, you need to join the worker nodes.

### Step 1: Get the join command

The master node automatically generates a join command. Retrieve it:

```bash
# From Windows host
vagrant ssh k8s-master -c "cat /vagrant/k8s-join-command.sh"
```

If the file doesn't exist, generate it manually:

```bash
vagrant ssh k8s-master -c "sudo kubeadm token create --print-join-command" > k8s-join-command.sh
```

### Step 2: Join worker-1

```bash
vagrant ssh k8s-worker-1 -c "sudo $(cat /vagrant/k8s-join-command.sh)"
```

Or SSH into the worker and run:

```bash
vagrant ssh k8s-worker-1
sudo $(cat /vagrant/k8s-join-command.sh)
exit
```

### Step 3: Join worker-2

```bash
vagrant ssh k8s-worker-2 -c "sudo $(cat /vagrant/k8s-join-command.sh)"
```

### Step 4: Verify all nodes are ready

```bash
vagrant ssh k8s-master -c "kubectl get nodes"
```

Expected output:
```
NAME           STATUS   ROLES           AGE   VERSION
k8s-master     Ready    control-plane   10m   v1.30.14
k8s-worker-1   Ready    <none>          2m    v1.30.14
k8s-worker-2   Ready    <none>          1m    v1.30.14
```

Wait 30-60 seconds for all nodes to show `Ready` status.

---

## Part 1: Installing Istio

### Step 1: Copy the script to the master node

From your Windows host, the files are already synced to `/vagrant/platform/` inside the VM.

```bash
# SSH into master
vagrant ssh k8s-master

# Navigate to Istio directory
cd /vagrant/platform/istio
```

### Step 2: Run the installation script

```bash
chmod +x install-istio.sh
./install-istio.sh
```

The script will:
1. Download Istio 1.27.2
2. Install using a **minimal profile** (reduced resources)
3. Configure Ingress Gateway with NodePort

### Step 3: Verify installation

```bash
kubectl get pods -n istio-system
```

Expected output:
```
NAME                                    READY   STATUS    RESTARTS   AGE
istio-ingressgateway-xxx                1/1     Running   0          2m
istiod-xxx                              1/1     Running   0          2m
```

### Step 4: Access the Ingress Gateway

The Ingress Gateway is exposed via NodePort:
- **HTTP**: Port `30080`
- **HTTPS**: Port `30443`

Access URL: `http://192.168.242.10:30080`

### Enabling Sidecar Injection

To enable automatic sidecar injection for your application namespace:

```bash
kubectl label namespace <your-namespace> istio-injection=enabled
```

### Uninstalling Istio

```bash
cd /vagrant/platform/istio
chmod +x uninstall-istio.sh
./uninstall-istio.sh
```

---

## Part 2: Installing Jenkins

### Step 1: Navigate to Jenkins directory

```bash
vagrant ssh k8s-master
cd /vagrant/platform/jenkins
```

### Step 2: Run the installation script

```bash
chmod +x install-jenkins.sh
./install-jenkins.sh
```

The script will:
1. Create the `jenkins` namespace
2. Set up RBAC permissions
3. Create storage (HostPath PV)
4. Deploy Jenkins with resource limits
5. Expose via NodePort 30808

### Step 3: Wait for Jenkins to start

Jenkins may take 2-3 minutes to fully start. Monitor progress:

```bash
kubectl -n jenkins get pods -w
```

Wait until STATUS shows `Running` and READY shows `1/1`.

### Step 4: Get the initial admin password

```bash
kubectl -n jenkins exec -it $(kubectl -n jenkins get pod -l app=jenkins -o jsonpath='{.items[0].metadata.name}') -- cat /var/jenkins_home/secrets/initialAdminPassword
```

Save this password for the next step.

### Step 5: Access Jenkins Web UI

Open your browser on the Windows host:

```
http://192.168.242.10:30808
```

1. Enter the initial admin password from Step 4
2. Choose "Install suggested plugins"
3. Create your admin user
4. Complete the setup wizard

### Recommended Plugins for Kubernetes

After setup, install these plugins via **Manage Jenkins > Plugins**:
- **Kubernetes** - For dynamic build agents
- **Pipeline** - For Jenkinsfile support
- **Git** - For SCM integration

### Uninstalling Jenkins

```bash
cd /vagrant/platform/jenkins
chmod +x uninstall-jenkins.sh
./uninstall-jenkins.sh
```

---

## Resource Summary

| Component | CPU Request | Memory Request | Memory Limit |
|-----------|-------------|----------------|--------------|
| istiod | 100m | 256Mi | 512Mi |
| istio-ingressgateway | 50m | 64Mi | 128Mi |
| istio sidecar (per pod) | 10m | 40Mi | 128Mi |
| Jenkins | 200m | 512Mi | 1Gi |

**Total estimated overhead**: ~900MB - 1.2GB RAM (fits within 9GB cluster)

---

## Access URLs Summary

| Service | URL | Port |
|---------|-----|------|
| Istio Ingress (HTTP) | http://192.168.242.10:30080 | 30080 |
| Istio Ingress (HTTPS) | https://192.168.242.10:30443 | 30443 |
| Jenkins | http://192.168.242.10:30808 | 30808 |

---

## Troubleshooting

### Pods stuck in Pending

Check node resources:
```bash
kubectl describe nodes | grep -A 5 "Allocated resources"
```

### Jenkins not starting

Check logs:
```bash
kubectl -n jenkins logs -f deployment/jenkins
```

### Istio installation fails

Ensure enough memory:
```bash
free -m
```

If memory is low, try stopping unnecessary services or restarting the VMs.
