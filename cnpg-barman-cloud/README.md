# Barman Cloud plugin (CloudNativePG backups)

Installs the [Barman Cloud CNPG-I plugin](https://cloudnative-pg.io/plugin-barman-cloud/) into
`cnpg-system` on clusters that run CloudNativePG databases. The plugin replaces the deprecated
in-tree `spec.backup.barmanObjectStore` and provides WAL archiving, base backups and recovery
against S3-compatible storage.

| Cluster | Fleet path | GitRepo (fleet-default on `local`) |
|---------|------------|------------------------------------|
| prd-apps | `cnpg-barman-cloud/overlays/prd-apps` | `gitops-core-cnpg-barman-cloud-prd-apps` |
| nprd-apps | `cnpg-barman-cloud/overlays/nprd-apps` | `gitops-core-cnpg-barman-cloud-nprd-apps` |

The GitRepos are defined in [fleet-gitrepos.yaml](fleet-gitrepos.yaml). poc-apps runs the
operator but has no CNPG clusters, so it has no overlay.

## Requirements

- CloudNativePG >= 1.26 (clusters run 1.28.0)
- cert-manager (the chart creates a self-signed Issuer and client/server certificates)
- Chart `plugin-barman-cloud` from `https://cloudnative-pg.github.io/charts`, pinned in each
  overlay's `fleet.yaml`. When upgrading, keep both overlays on the same version.

## Where the backups go

Each database cluster defines its own `ObjectStore` and `ScheduledBackup` in the repo that owns
the database (gitops-dev: coder, gitops-mcp: high-command, gitops-tools: authentik and harbor).
All write to rustfs at `https://rustfs.dataknife.net:30292` (Let's Encrypt certificate, no custom
CA needed) under:

```
s3://rke2-backups/cnpg/<k8s-cluster>/<cnpg-cluster>/{base,wals}
```

The S3 credentials live in a `cnpg-backup-rustfs` Secret (keys `ACCESS_KEY_ID`,
`ACCESS_SECRET_KEY`) in each database namespace. It is created by hand and is not in git.

## Checking status

```bash
kubectl -n cnpg-system rollout status deploy/plugin-barman-cloud
kubectl cnpg status <cluster> -n <ns>             # "Continuous Backup status" section
kubectl -n <ns> get clusters.postgresql.cnpg.io <cluster> \
  -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")]}'
kubectl -n <ns> get backups.postgresql.cnpg.io,scheduledbackups.postgresql.cnpg.io
kubectl -n <ns> get objectstores.barmancloud.cnpg.io <store> -o jsonpath='{.status}'
```

On-demand backup:

```bash
kubectl cnpg backup <cluster> -n <ns> --method=plugin --plugin-name=barman-cloud.cloudnative-pg.io
```

## Restoring

Recovery always creates a new cluster. Point `bootstrap.recovery` at an external cluster that
reads the existing ObjectStore with `serverName` set to the original cluster name:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: <cluster>-restore
spec:
  instances: 1
  storage:
    size: 10Gi
    storageClass: truenas-csi-nfs
  bootstrap:
    recovery:
      source: origin
      # recoveryTarget:
      #   targetTime: "2026-10-05 01:00:00+00"
  externalClusters:
    - name: origin
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: <store>
          serverName: <original-cluster-name>
```

Do not enable `spec.plugins` WAL archiving on the restored cluster against the same
`serverName`. Use a different `serverName` parameter, or a separate ObjectStore, so the
original archive is not overwritten. Once the restore is verified, switch the application
over (or rename) and re-enable backups.
