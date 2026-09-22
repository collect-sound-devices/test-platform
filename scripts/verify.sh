#!/usr/bin/env bash
# Static validation. Runs the two linters as pinned containers, so nothing has to be
# installed on the host and CI runs the identical versions.
set -euo pipefail

OVERLAY="${OVERLAY:-overlays/dev}"
KUBECONFORM_IMAGE="ghcr.io/yannh/kubeconform:v0.6.7"
KUBE_SCORE_IMAGE="zegl/kube-score:v1.20.0"

# Deliberate omissions, justified in the README and in claude/build-log.md:
#   pod-networkpolicy      kindnet does not enforce NetworkPolicy, so the manifest would
#                          be inert, and an inert manifest is worse than none (brief §9).
#   container-image-pull-policy
#                          brief §7 mandates IfNotPresent; Always would force a registry
#                          round-trip on every restart of an explicitly pinned tag.
IGNORED_TESTS=(
  "pod-networkpolicy"
  "container-image-pull-policy"
)

cd "$(dirname "$0")/.."

ignore_args=()
for t in "${IGNORED_TESTS[@]}"; do
  ignore_args+=(--ignore-test "$t")
done

echo "==> kustomize build $OVERLAY"
kubectl kustomize "$OVERLAY" > /tmp/test-platform-built.yaml
echo "    $(grep -c '^kind:' /tmp/test-platform-built.yaml) resources built"

echo
echo "==> kubeconform ($KUBECONFORM_IMAGE)"
docker run -i --rm "$KUBECONFORM_IMAGE" -strict -summary - < /tmp/test-platform-built.yaml

echo
echo "==> kube-score ($KUBE_SCORE_IMAGE)"
echo "    suppressed: ${IGNORED_TESTS[*]}"
docker run -i --rm "$KUBE_SCORE_IMAGE" score "${ignore_args[@]}" - < /tmp/test-platform-built.yaml

echo
echo "==> Static validation passed."
