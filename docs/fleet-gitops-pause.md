# Pausing and resuming Fleet for this repo

Use this when you need to apply cluster changes manually (or merge Git changes) **without Fleet immediately reconciling** and overwriting resources.

## Pause: disable the GitRepo

On the **management cluster** (Fleet runs here; often the same cluster as Rancher), disable the `gitops-core` GitRepo:

```bash
kubectl patch gitrepo gitops-core -n fleet-default --type=merge -p '{"spec":{"disabled":true}}'
```

Confirm:

```bash
kubectl get gitrepo gitops-core -n fleet-default -o jsonpath='{.spec.disabled}{"\n"}'
```

Expected: `true`

## Resume

```bash
kubectl patch gitrepo gitops-core -n fleet-default --type=merge -p '{"spec":{"disabled":false}}'
```

Fleet will reconcile from `branch` / `paths` in [fleet-gitrepo.yaml](../fleet-gitrepo.yaml).

If `spec.disabled` is not available on your Rancher/Fleet version, use **Continuous Delivery → Git Repos → gitops-core** in the Rancher UI and pause/resume there, or scale the controllers below.

## Alternative: scale Fleet controllers (heavier hammer)

Only if your Fleet version does not support `spec.disabled` or you need to stop all GitOps:

```bash
kubectl -n cattle-fleet-system scale deployment fleet-controller --replicas=0
kubectl -n cattle-fleet-local-system scale deployment fleet-agent --replicas=0
```

Restore:

```bash
kubectl -n cattle-fleet-system scale deployment fleet-controller --replicas=1
kubectl -n cattle-fleet-local-system scale deployment fleet-agent --replicas=1
```

(Replica counts may differ in your environment; use `kubectl get deploy -n cattle-fleet-system` first.)
