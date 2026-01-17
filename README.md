# GitOps Core

GitOps repository for core infrastructure services, focusing on certificate management via CloudFlare and Let's Encrypt.

## Overview

This repository hosts the core service configuration for automatic TLS certificate management using:
- **cert-manager**: Kubernetes certificate management operator
- **Let's Encrypt**: Free TLS certificate authority
- **CloudFlare**: DNS provider for DNS-01 challenge validation

## Quick Start

See [cert-manager/README.md](cert-manager/README.md) for detailed setup and usage instructions.

## Structure

```
.
└── cert-manager/   # Certificate management via CloudFlare and Let's Encrypt
    ├── base/       # Base configurations (reusable across clusters)
    └── overlays/   # Cluster-specific overlays
```

## Services

- **Cert-Manager**: Automatic wildcard certificate provisioning and renewal for `*.dataknife.net` and `*.dataknife.ai` domains

## Deployment

This repository is designed to be deployed via Rancher Fleet or other GitOps tools. Each overlay contains cluster-specific configurations.

## Contributing

See individual service directories for service-specific documentation and setup instructions.
