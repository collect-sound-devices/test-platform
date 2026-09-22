# test-platform

A Kubernetes demo that runs from a clean machine with one command and shows operational practice:
namespaces, probes, limits, secrets, a stateful broker with persistent storage, and message delivery
semantics with retry and dead-letter handling.

**The build brief is `claude/initial-prompt-info.md`.** Read it before starting work — it defines scope,
stages, acceptance criteria and what is deliberately out of scope. Do not begin a stage before the
previous one is approved.

## Paths

| | |
|---|---|
| This repository | `~/DWP/collect-sound-devices/test-platform` |
| Reference lab, **read only** | `~/DWP/collect-sound-devices/test-infrastructure` |
| Forwarder sources, for config keys | `~/DWP/collect-sound-devices/rmq-to-rest-api-forwarder` |

## Checks

Run these before proposing any commit, and paste the output. A claim of success without output is not
a result. (The first two apply from Stage 1, once `base/` and `overlays/` exist.)

```bash
kustomize build overlays/dev | kubeconform -strict -summary -
kustomize build overlays/dev | kube-score score -
make down && make up          # must end with all pods Ready
```

## Hard rules

- Never commit credentials. Secrets are created at deploy time; the repository holds only
  `secret.example.yaml` with the key names.
- No package installation at container runtime. If an image lacks something, that is a finding to
  report, not a startup script to write.
- Pin every image tag. Never `latest`. **No image is built in this repository** — if a component needs
  one that does not exist publicly, report it instead of building it.
- Every container: `requests` and `limits`, a readiness probe and a liveness probe that are **not the
  same check**, and the restricted Pod Security Standard (brief §7).
- Append to `claude/build-log.md` after each completed unit of work. Format and rules: brief §12.

## Gotchas

- kindnet does not enforce NetworkPolicy. `kube-score` will warn about a missing NetworkPolicy, and
  about PodDisruptionBudget for single-replica workloads. Both are deliberate omissions: suppress the
  check and say why in the log. Never add a manifest that has no effect just to silence a linter.
- The history of `test-infrastructure` contains plaintext broker credentials and a runtime `apt-get`
  step. Never import it, and never copy those patterns forward.
- The forwarder is a .NET service: its settings map to environment variables as `Section__Key`.

## Working style

- YAGNI. Build what the brief asks for, not what it might need later.
- State facts once. A detail belongs in the README, in a comment next to the manifest, or in the build
  log — not in all three.
- Say when something is unverified instead of guessing. Step 0 of the brief exists for exactly this.
- Edit files in place. Never retype file content from truncated command output.
- Report contradictions rather than resolving them silently — which version is right is my call.
- Report what does not work instead of routing around it.
