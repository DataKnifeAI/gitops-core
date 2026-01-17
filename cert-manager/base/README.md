# Cert-Manager Base Configuration

This directory contains the base configuration for cert-manager to automatically provision and renew Let's Encrypt wildcard certificates.

## Overview

This configuration provides:
- **ClusterIssuer**: Let's Encrypt issuer using DNS-01 challenge (required for wildcards)
- **Certificates**: Automatic certificate provisioning for `*.dataknife.net` and `*.dataknife.ai`

## Prerequisites

1. **cert-manager must be installed** on the cluster (already installed on nprd-apps)
2. **DNS provider credentials** must be configured in the overlay (see below)
3. **DNS zones** must be accessible and manageable via API

## DNS-01 Challenge

Wildcard certificates require DNS-01 challenge validation. This means cert-manager needs:
- API access to your DNS provider
- Credentials (API token/key) stored in a Kubernetes secret

### Supported DNS Providers

cert-manager supports many DNS providers. Common ones include:

- **Cloudflare**: Most popular, easy setup with API tokens
- **Route53**: For AWS-hosted DNS
- **Google Cloud DNS**: For GCP DNS
- **Azure DNS**: For Azure DNS
- **DigitalOcean**: For DigitalOcean DNS
- **Many others**: See [cert-manager DNS01 providers documentation](https://cert-manager.io/docs/configuration/acme/dns01/)

## Configuration in Overlays

Each cluster overlay must:

1. **Configure the DNS provider** in `clusterissuer.yaml`
2. **Create DNS provider secret** (not stored in Git - see secrets directory)
3. **Override email** if needed (different from base)

### Example: Cloudflare Configuration

In `overlays/{cluster}/clusterissuer.yaml`:

```yaml
spec:
  acme:
    email: admin@dataknife.net  # Override if needed
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
      selector:
        dnsNames:
        - "*.dataknife.net"
        - "dataknife.net"
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
      selector:
        dnsNames:
        - "*.dataknife.ai"
        - "dataknife.ai"
```

Create the secret:

```bash
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=your-cloudflare-api-token-here \
  -n cert-manager
```

### Example: Route53 Configuration

In `overlays/{cluster}/clusterissuer.yaml`:

```yaml
spec:
  acme:
    email: admin@dataknife.net
    solvers:
    - dns01:
        route53:
          region: us-east-1
          accessKeyID: YOUR_ACCESS_KEY_ID
          secretAccessKeySecretRef:
            name: route53-credentials
            key: secret-access-key
      selector:
        dnsNames:
        - "*.dataknife.net"
        - "dataknife.net"
```

Create the secret:

```bash
kubectl create secret generic route53-credentials \
  --from-literal=secret-access-key=your-secret-key-here \
  -n cert-manager
```

## Certificate Resources

The base configuration includes two Certificate resources:

1. **wildcard-dataknife-net**: Creates `wildcard-dataknife-net-tls` secret
2. **wildcard-dataknife-ai**: Creates `wildcard-dataknife-ai-tls` secret

These certificates will be automatically renewed by cert-manager 30 days before expiration.

## Using Certificates in Ingress

Once certificates are issued, use them in Ingress resources:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
spec:
  tls:
    - hosts:
        - app.dataknife.net
      secretName: wildcard-dataknife-net-tls  # Secret from Certificate
  rules:
    - host: app.dataknife.net
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-service
                port:
                  number: 80
```

### Sharing Certificates Across Namespaces

By default, Certificate resources create secrets in the same namespace (`cert-manager`). To use in other namespaces:

**Option 1**: Copy the secret to other namespaces (manual):
```bash
kubectl get secret wildcard-dataknife-net-tls -n cert-manager -o yaml | \
  sed 's/namespace: cert-manager/namespace: your-namespace/' | \
  kubectl apply -f -
```

**Option 2**: Create Certificate resources per namespace (recommended for GitOps):
Create Certificate resources in each namespace where needed, or modify the base Certificate to use a different namespace/secret distribution strategy.

## Verification

Check certificate status:

```bash
# Check ClusterIssuer
kubectl get clusterissuer letsencrypt-dns01

# Check Certificates
kubectl get certificates -n cert-manager

# Check certificate details
kubectl describe certificate wildcard-dataknife-net -n cert-manager

# Check certificate secret
kubectl get secret wildcard-dataknife-net-tls -n cert-manager
```

Check certificate order/challenge status:

```bash
# List certificate requests
kubectl get certificaterequests -n cert-manager

# List ACME challenges
kubectl get challenges -n cert-manager

# List ACME orders
kubectl get orders -n cert-manager
```

## Troubleshooting

### Certificate Not Issuing

1. **Check ClusterIssuer status**: `kubectl describe clusterissuer letsencrypt-dns01`
2. **Check Certificate status**: `kubectl describe certificate wildcard-dataknife-net -n cert-manager`
3. **Check CertificateRequest**: `kubectl get certificaterequest -n cert-manager`
4. **Check ACME Order**: `kubectl get order -n cert-manager`
5. **Check DNS provider secret**: Ensure the secret exists and has correct keys
6. **Check DNS API access**: Verify DNS provider credentials have API access
7. **Check rate limits**: Let's Encrypt has rate limits (50 certs/week per registered domain)

### DNS Provider Issues

- Ensure API token/key has correct permissions
- For Cloudflare: API token needs `Zone:Edit` permission
- For Route53: IAM user needs `route53:ChangeResourceRecordSets` permission
- Check DNS provider logs in cert-manager pod logs

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [ACME DNS-01 Challenge](https://cert-manager.io/docs/configuration/acme/dns01/)
- [DNS Provider Configuration](https://cert-manager.io/docs/configuration/acme/dns01/)
