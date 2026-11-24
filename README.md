# :rocket: HashiCorp Vault Dynamic Secrets Agent

<p align="center">
  <img src="docs/images/architecture-white.jpg" width="100%" />
</p>

<div align="center">

[![Status](https://img.shields.io/badge/status-production--ready-brightgreen?style=for-the-badge&logo=git)]()
[![Domain](https://img.shields.io/badge/domain-Kubernetes--and--Vault--Security-blueviolet?style=for-the-badge)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=for-the-badge&logo=github)](https://github.com/tayyabmasood911/hashicorp-vault-dynamic-secrets-agent/pulls)
[![Security Hardened](https://img.shields.io/badge/security-hardened-red?style=for-the-badge&logo=shield)]()

</div>

---

## :memo: Executive Summary

**HashiCorp Vault Dynamic Secrets Agent** delivers an enterprise-grade cloud-native security pattern for managing ephemeral, automatically-rotated credentials inside Kubernetes. By pairing the **Vault Agent Sidecar** and **Vault Agent Injector** with HashiCorp Vault's **Database Dynamic Secrets Engine**, this repository completely eliminates long-lived static database passwords from source code, configuration files, Helm charts, and CI/CD pipelines.

Key operational outcomes:
- **Zero Static Credentials:** Every application pod receives a unique, ephemeral PostgreSQL database username and password generated dynamically at runtime.
- **Automated Lifecycle & Renewal:** Vault Agent automatically negotiates token renewal and background lease extensions without manual intervention.
- **In-Memory RAM Delivery:** Dynamic secrets are rendered directly into an ephemeral memory-backed volume (`emptyDir: medium: Memory`), leaving zero traces on persistent disk.
- **Zero-Downtime Secret Rotation:** When credentials reach TTL expiration or undergo rotation, Vault Agent issues a non-disruptive `SIGHUP` reload signal to the application container.

---

## :building_construction: System Architecture

The following diagram illustrates the token authentication handshake and dynamic secret provisioning lifecycle:

```text
+---------------------------------------------------------------------------------------------------+
|               HashiCorp Vault Dynamic Secrets & Agent Sidecar Architecture Blueprint              |
|                                                                                                   |
|   [Kubernetes Pod Boundary]                                                                       |
|   +---------------------------------------+       TokenReview API Validation                      |
|   | [Vault Agent Sidecar Container]       | ================================> [Vault Cluster]     |
|   | - Auto-Auth: auth/kubernetes          |                                   (Address: :8200)    |
|   | - Projected ServiceAccount Token      | <================================                     |
|   +---------------------------------------+       Scoped Short-Lived Vault Client Token           |
|                       |                                                                           |
|                       v Dynamic Secrets Request: database/creds/readonly                          |
|   +---------------------------------------+                                                       |
|   | [Consul Template Engine]              |                                                       |
|   | - Reads template-database.ctmpl       | <================================ [Vault Database]    |
|   | - Formats dynamic secrets             |       Generates Temporary User & Lease (1h TTL)       |
|   +---------------------------------------+                                                       |
|                       |                                                                           |
|                       v Renders Secret File                                                       |
|   +---------------------------------------+       Reads Credentials In-Memory (Read-Only)         |
|   | [Shared Memory Volume (/vault/secrets)] ================================> [Application Pod]  |
|   | - database.env (Perms: 0600)          |                                   (Connects to DB)    |
|   +---------------------------------------+                                           |           |
|                                                                                       v           |
|                                                                           [PostgreSQL Database]   |
|                                                                           (Least-Privilege SELECT)|
+---------------------------------------------------------------------------------------------------+
```

> High-resolution architectural vector diagram is available at [`docs/images/architecture.svg`](docs/images/architecture.svg).

---

## :sparkles: Key Enterprise Capabilities

- :key: **Dynamic Ephemeral Credentials:** Database users are created just-in-time (`CREATE ROLE ... WITH LOGIN`) and automatically destroyed (`DROP ROLE`) upon TTL expiration.
- :lock: **Kubernetes ServiceAccount Authentication:** Native `auth/kubernetes` integration leverages Kubernetes token projection without storing hardcoded Vault tokens.
- :memo: **Consul Template Formatting:** Renders connection strings, username/password pairs, and lease metadata directly into environment variable formats.
- :arrows_counterclockwise: **Process Signal Reloads:** Configurable `command = "kill -HUP 1 || true"` in `vault-agent-config.hcl` triggers application re-authentication seamlessly.
- :rocket: **Dual Deployment Patterns:** Fully documented support for both the explicit **Sidecar Container** pattern and the annotation-driven **Vault Agent Injector** pattern.
- :shield: **SOC 2 & PCI-DSS Compliance:** Fulfills regulatory standards requiring unique user attribution, strict credential expiration, and automated rotation.

---

## :file_folder: Repository Directory Structure

```text
.
|-- .github/
|   `-- workflows/
|       `-- ci.yml                   # Automated validation CI pipeline
|-- config/
|   `-- production.env.example       # Baseline production environment variables
|-- docs/
|   `-- images/
|       |-- architecture-white.jpg   # High-resolution architectural overview
|       `-- architecture.svg         # Detailed vector topology blueprint
|-- scripts/
|   `-- healthcheck.sh               # Health check verification script
|-- tests/
|   `-- test_validation.py           # Integrity test suite
|-- serviceaccount.yaml              # RBAC ServiceAccount and TokenReview binding
|-- template-database.ctmpl          # Dynamic PostgreSQL credential Consul template
|-- vault-agent-config.hcl           # Production Vault Agent daemon configuration
|-- vault-agent-sidecar-pod.yaml     # Kubernetes Deployment with Vault Agent sidecar
|-- vault-injector-deployment.yaml   # Mutation webhook annotation-driven deployment
|-- .gitattributes                   # GitHub Linguist language overrides
|-- LICENSE                          # MIT License
|-- Makefile                         # Automation lifecycle targets
|-- README.md                        # Production documentation
`-- SECURITY.md                      # Vulnerability reporting policy
```

---

## :clipboard: Prerequisites

Ensure your cluster satisfies the following baseline requirements:

| Component | Minimum Version | Description |
| :--- | :--- | :--- |
| **Kubernetes** | `>= 1.28.0` | EKS, GKE, AKS, or bare-metal cluster with TokenRequest enabled |
| **HashiCorp Vault** | `>= 1.15.0` | Vault server cluster with `database` and `kubernetes` auth mounts enabled |
| **PostgreSQL** | `>= 14.0` | Target database configured with Vault admin provisioning user |
| **kubectl** | `>= 1.28.0` | Standard Kubernetes command-line interface |
| **Helm** | `>= 3.12.0` | For deploying the Vault Agent Injector helm chart |

---

## :zap: Quick Start & Deployment Guide

### 1. Configure Vault Kubernetes Authentication & Database Engine
Execute on your HashiCorp Vault server (or via Vault CLI):

```bash
# Enable Kubernetes authentication
vault auth enable kubernetes

# Configure Vault with Kubernetes cluster host and JWT token review
vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc:443"

# Create Vault application role mapped to the ServiceAccount
vault write auth/kubernetes/role/app-role \
    bound_service_account_names=vault-auth-sa \
    bound_service_account_namespaces=default \
    policies=database-readonly \
    ttl=1h

# Enable and configure dynamic database secrets engine
vault secrets enable database
vault write database/config/production-postgres \
    plugin_name=postgresql-database-plugin \
    allowed_roles="readonly" \
    connection_url="postgresql://{{username}}:{{password}}@postgres.database.svc.cluster.local:5432/production_db?sslmode=verify-full" \
    username="vault_admin" \
    password="super_secure_vault_admin_password"

# Define dynamic role with 1-hour lease and automatic DROP ROLE
vault write database/roles/readonly \
    db_name=production-postgres \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"
```

### 2. Deploy Kubernetes RBAC
Apply the dedicated ServiceAccount and cluster authentication delegator binding:

```bash
kubectl apply -f serviceaccount.yaml
```

### 3. Deploy Application with Vault Agent Sidecar
Mount the agent configuration as a ConfigMap and deploy the multi-container pod:

```bash
# Create ConfigMap containing Vault Agent HCL and Consul Template
kubectl create configmap vault-agent-config \
    --from-file=vault-agent-config.hcl \
    --from-file=template-database.ctmpl \
    --dry-run=client -o yaml | kubectl apply -f -

# Deploy application pod with Vault Agent sidecar
kubectl apply -f vault-agent-sidecar-pod.yaml
```

### 4. Alternative: Deploy via Vault Agent Injector Annotations
If your cluster runs the Vault Agent Injector mutating webhook:

```bash
kubectl apply -f vault-injector-deployment.yaml
```

### 5. Verify In-Memory Dynamic Secrets
Verify that dynamic credentials have been mounted inside the application pod:

```bash
# Inspect generated dynamic secret file
kubectl exec -it deployment/payment-service -c app -- cat /vault/secrets/database.env

# Inspect Vault Agent logs for successful authentication & renewal
kubectl logs -f deployment/payment-service -c vault-agent
```

---

## :gear: Configuration Reference

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `vault.address` | string | `https://vault.internal:8200` | Target HashiCorp Vault cluster API endpoint |
| `auto_auth.role` | string | `app-role` | Vault Kubernetes auth role mapped to ServiceAccount |
| `template.destination` | string | `/vault/secrets/database.env` | In-memory path for rendered application secrets |
| `template.perms` | string | `0600` | Strict file permissions restricting read access |
| `cache.use_auto_auth_token` | boolean | `true` | Persistent token caching to optimize Vault cluster load |
| `database default_ttl` | duration | `1h` | Automatic expiration window for dynamic database users |
| `database max_ttl` | duration | `24h` | Hard ceiling for dynamic lease duration |

---

## :lock: Security, Compliance & Governance

1. **Least-Privilege Database Roles:** Ephemeral users are restricted strictly to read-only `SELECT` permissions.
2. **RAM-Only Ephemeral Storage:** `emptyDir.medium: Memory` guarantees that dynamic credentials disappear immediately on container restart.
3. **Audit Trail Accountability:** Every generated username (`v-token-app-role-*`) is timestamped and recorded in the Vault audit device.
4. **Zero Shared Secrets:** Every single replica instance in a deployment receives an isolated database user and independent lease.

---

## :bust_in_silhouette: Author & Maintainer

**Tayyab Masood**  
Cloud Solutions Architect & Senior DevOps Engineer  
- :globe_with_meridians: **GitHub:** [@tayyabmasood911](https://github.com/tayyabmasood911)  
- :email: **Email:** tayyabmasood911@gmail.com  
- :scroll: **Certification:** AWS Certified Solutions Architect - Associate  

---

## :page_facing_up: License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.
