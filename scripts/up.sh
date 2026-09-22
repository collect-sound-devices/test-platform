#!/usr/bin/env bash
# Create the cluster, create the Secret, apply the overlay, wait for readiness.
# Idempotent: running it against an existing cluster re-applies and re-waits.
set -euo pipefail

CLUSTER="${CLUSTER:-test-platform}"
NAMESPACE="${NAMESPACE:-test-platform}"
OVERLAY="${OVERLAY:-overlays/dev}"
SECRET="rabbitmq-credentials"

cd "$(dirname "$0")/.."

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "==> Cluster '$CLUSTER' already exists, reusing it."
else
  echo "==> Creating kind cluster '$CLUSTER' (1 control-plane + 2 workers)..."
  kind create cluster --name "$CLUSTER" --config kind/kind-config.yaml --wait 120s
fi

kubectl config use-context "kind-$CLUSTER" >/dev/null

# The namespace has to exist before the Secret can be put in it, and the Secret has to
# exist before the workloads start, or they crash-loop on a missing reference.
echo "==> Applying namespace..."
kubectl apply -f base/namespace.yaml

if kubectl -n "$NAMESPACE" get secret "$SECRET" >/dev/null 2>&1; then
  echo "==> Secret '$SECRET' already exists, keeping it."
else
  echo "==> Creating Secret '$SECRET' with a generated password..."
  # Generated here and never written to disk: the repository holds only
  # base/secret.example.yaml, which documents the key names (brief §7).
  kubectl -n "$NAMESPACE" create secret generic "$SECRET" \
    --from-literal=username=demo \
    --from-literal=password="$(openssl rand -base64 24 | tr -d '\n=/+' | cut -c1-24)"
fi

echo "==> Applying $OVERLAY..."
kubectl apply -k "$OVERLAY"

echo "==> Waiting for the broker to become Ready (image pull can take a while)..."
kubectl -n "$NAMESPACE" rollout status statefulset/rabbitmq --timeout=300s

echo "==> Waiting for the sink and the forwarder..."
kubectl -n "$NAMESPACE" rollout status deployment/sink --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/forwarder --timeout=300s

echo "==> Waiting for the publisher Job to complete..."
kubectl -n "$NAMESPACE" wait --for=condition=complete job/publisher --timeout=300s

echo
echo "==> All workloads ready."
kubectl -n "$NAMESPACE" get pods -o wide
