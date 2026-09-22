# test-platform — build brief

Technical brief for an agent-driven build of this repository. It defines scope, target state and
acceptance criteria. It is not a tutorial and contains no step-by-step commands beyond those needed
to state an acceptance test.

## 1. Goal

A small, self-contained Kubernetes demo that runs from a clean machine with one command and
demonstrates operational practice: namespaces, probes, resource limits, secrets and config maps,
a stateful broker with persistent storage, and message delivery semantics with retry and dead-letter
handling.

It replaces the ad-hoc lab in `test-infrastructure`, which demonstrates cluster setup but not operation.

## 2. Repositories and paths

| Role | Path | Access |
|---|---|---|
| Target | `~/DWP/collect-sound-devices/test-platform` | read/write |
| Source / reference | `~/DWP/collect-sound-devices/test-infrastructure` | **read only — never modify** |
| Forwarder sources | `~/DWP/collect-sound-devices/rmq-to-rest-api-forwarder` | read only, for configuration keys |

Remote of the target: `https://github.com/collect-sound-devices/test-platform` (public).
Do not re-clone or re-initialise it.

The two reference paths are outside the working directory and must be granted to the session.
`.claude/settings.local.json` in this repository does that for every session, CLI and desktop app alike:

```json
{ "permissions": { "additionalDirectories": ["../test-infrastructure", "../rmq-to-rest-api-forwarder"] } }
```

The key takes effect once the folder is trusted, which Claude Code asks about on first start.
From the CLI the same is possible per session with `claude --add-dir ../test-infrastructure
--add-dir ../rmq-to-rest-api-forwarder`, or mid-session with `/add-dir`. The desktop app has no UI
control for it: local sessions there work with a single project folder.

Do not import history from `test-infrastructure`: plaintext broker credentials and a runtime
`apt-get` step exist in its old commits.

## 3. Current state of the target repository

- `LICENSE` — MIT. Leave unchanged.
- `.gitignore` at the root — 0 bytes.
- `.idea/` — JetBrains project files, partly tracked and pushed (`.idea/.gitignore`, `encodings.xml`,
  `indexLayout.xml`, `vcs.xml`).
- `claude/` — holds this brief.
- No `README.md`.

## 4. What to carry over from `test-infrastructure`, and what to fix

Carried over: kind cluster from a config file, deployments, services, DNS-based service discovery,
the Gateway API / Ingress example (optional here).

Dropped: the sound scanner and its PulseAudio sidecar. It installs packages at container start,
needs a fake audio device, and demonstrates nothing operational.

| Defect in `test-infrastructure` | Location | Required in `test-platform` |
|---|---|---|
| `guest`/`guest` as plaintext env | `k8s/messaging-client-deployment.yaml` | Secret, created in-cluster, never committed |
| `apt-get` at container runtime | `k8s/scanner-client-deployment.yaml` | dropped with the scanner |
| no namespace (everything in `default`) | all manifests | namespace `test-platform` |
| no probes, no limits | all manifests | probes and requests/limits on every container |
| broker as Deployment, no volume | `messaging-client-deployment.yaml` | StatefulSet with PVC |
| `imagePullPolicy: Never` plus `kind load` | `scanner-client-deployment.yaml`, README | public images, `IfNotPresent` |
| README as a list of commands | `README.md` | one start command, the rest documented |

## 5. Target workload

Chain: **publisher → RabbitMQ → RmqToRestApiForwarder → REST sink**

Images (all public, tags verified on Docker Hub 2026-09-19; no image is built in this repository):

| Component | Image |
|---|---|
| Broker | `rabbitmq:3.13-management` |
| Forwarder | `danzigereduard/rmq-to-rest-api-forwarder:v3.4.3` |
| Publisher | `rabbitmq:3.13-management`, using `rabbitmqadmin` from a Job or CronJob |
| REST sink | `audio-device-repo-server` if a public image exists, otherwise `ealen/echo-server` |

Pin every tag explicitly. Never use `latest`.

## 6. Delivery semantics — the part that matters

Per its README, the forwarder implements an event-forwarding pattern with a TTL-driven retry queue,
a failed queue, ACK semantics and debouncing of frequent volume-change events. Relevant settings:

- `RabbitMQ:MessageDelivery:RetryDelayInSeconds`
- `RabbitMQ:MessageDelivery:MaxRetryAttempts`
- `RabbitMQ:MessageDelivery:VolumeChangeEventDebouncingWindowInMilliseconds`

In Kubernetes these are environment variables in .NET notation, `Section__Key`:

```
RabbitMQ__MessageDelivery__RetryDelayInSeconds
RabbitMQ__MessageDelivery__MaxRetryAttempts
RabbitMQ__MessageDelivery__VolumeChangeEventDebouncingWindowInMilliseconds
```

The section path is `RabbitMQ:MessageDelivery`, bound in `Program.cs` by
`config.GetSection("RabbitMQ:MessageDelivery")`. The forwarder's own README calls it
`RabbitMqMessageDeliverySettings`, which is the name of the C# record the section binds *to*, not a
configuration path — that name does not work as an environment variable. Verified 2026-09-22 against
`v3.4.3`: the container echoes every bound value on startup in its "Consumer service parameters
initialized" log line.

The repository must be able to demonstrate, reproducibly:

1. sink returns success → message is delivered, visible in the sink log
2. sink returns an error → message moves to the `.retry` queue, is redelivered after the TTL, and
   lands in the `.failed` queue once `MaxRetryAttempts` is exhausted
3. both observable in the RabbitMQ management UI via port-forward

Provide this as a script (`scripts/demo-retry.sh`), not as prose in the README.

## 7. Operational requirements

| Requirement | Implementation |
|---|---|
| Namespace | `test-platform`, set on every object |
| Probes | broker: `rabbitmq-diagnostics -q ping` (readiness) and `-q status` (liveness); sink: HTTP probes; forwarder: see §10 |
| Resource limits | requests and limits on every container |
| Secrets | broker credentials as a Secret created at deploy time, never committed; `secret.example.yaml` documents the keys |
| ConfigMap | queue names, sink base URL, retry and debounce settings |
| Persistence | broker as StatefulSet with `volumeClaimTemplates` and a headless service; `kubectl delete pod rabbitmq-0` must not lose enqueued messages |
| Images | public, version-pinned, `imagePullPolicy: IfNotPresent`, no `kind load` |
| Single start command | `make up`: create cluster, create secret, apply, wait for readiness |
| Kustomize | `base/` plus `overlays/dev` and `overlays/demo` |
| RBAC | ServiceAccount, Role and RoleBinding with least privilege |
| Multi-node | kind config with one control-plane and two workers |
| Pod security | every container satisfies the **restricted** Pod Security Standard: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`. Enforce it on the namespace with the `pod-security.kubernetes.io/enforce: restricted` label. If an upstream image cannot run non-root, report it instead of weakening the namespace |
| Labels | the recommended set on every object: `app.kubernetes.io/name`, `/instance`, `/version`, `/component`, `/part-of`, `/managed-by` |
| Static validation | `kustomize build <overlay> | kubeconform -strict -summary -` and `| kube-score score -` both pass, or a suppressed check is justified in the log (§9) |

## 8. Repository layout

```
test-platform/
├── README.md              architecture, one start command, the three demo steps, stated limits,
│                       tested tool versions (kind, kubectl, kustomize), "not for production" note
├── LICENSE                exists
├── .gitignore             to fill: .idea/, .claude/settings.local.json, .claude/worktrees/,
│                       *.local.yaml, secret.yaml, kubeconfig
├── Makefile               up / down / demo / verify
├── kind/kind-config.yaml  control-plane + 2 workers
├── base/                  namespace, configmap, secret.example, rabbitmq StatefulSet + services,
│                          forwarder Deployment + service, sink, publisher Job, rbac
├── overlays/dev|demo/     replicas, resources, log level
├── scripts/               up.sh, demo-retry.sh, verify.sh
├── claude/                this brief, build-log.md (§12)
└── .github/workflows/     ci.yaml: kubeconform, kind, readiness wait, log assertion
```

## 9. Out of scope

- **NetworkPolicy** — kindnet does not enforce it by default. A manifest that has no effect is worse
  than none.
- **PodDisruptionBudget** — meaningless for the single-replica workloads here.

  `kube-score` flags both. Suppress those two checks explicitly and record why in the build log.
  Do not add an inert manifest to make a linter quiet.
- Helm — Kustomize is sufficient here.
- Service mesh, Prometheus stack, autoscaling.
- Any image build. If a component needs an image that does not exist publicly, report it instead of
  building one.

## 10. Step 0 — verify before writing manifests

These are unverified. Check them, report the findings, and wait for a decision before assuming either way.

1. Does `audio-device-repo-server` have a publicly pullable image (Docker Hub `danzigereduard/*`
   or `ghcr.io/collect-sound-devices/*`)? If not, the sink is `ealen/echo-server`.
2. Does `danzigereduard/rmq-to-rest-api-forwarder:v3.4.3` start standalone, and which environment
   variables does it actually read? Sources are available locally (§2).
3. Does the forwarder expose an HTTP health endpoint? If not, use an exec probe or omit the probe
   and say so in the README.
4. Which message payload does the forwarder accept? The publisher must produce that shape, otherwise
   the demo only shows parse errors.

## 11. Stages

Each stage is verified before the next begins.

- **Stage 0 — hygiene.** Fill the root `.gitignore` (§8), `git rm -r --cached .idea`, README skeleton.
  One commit. Keep `.claude/settings.json`, skills and agents committable — only the local settings
  file and the worktrees directory are ignored. Do not modify `LICENSE`, `CLAUDE.md` or this brief.
- **Stage 1 — core.** Namespace, ConfigMap, Secret, broker StatefulSet with PVC, forwarder, sink,
  publisher Job, probes, limits, `make up`, README.
- **Stage 2 — CI.** GitHub Actions: `kubeconform` over all manifests, then `helm/kind-action`,
  apply, `kubectl wait --for=condition=Ready` with a timeout, run the publisher, assert on the sink log.
  Badge in the README. A red badge is worse than no badge: if the workflow is not green, remove it
  until it is.
- **Stage 3 — extensions.** Kustomize overlays, `demo-retry.sh`, RBAC, metrics-server, multi-node cluster.

## 12. Build log

Keep `claude/build-log.md`, append-only. It is a decision log, not a transcript.

**Write one entry per completed unit of work** — a stage, a Step 0 finding, a component of Stage 1,
a CI iteration that produced a lesson. Not per command and not per file.

Entry format, four short parts:

```
## <date> — <what was done>
Goal:      one line — what this had to achieve
Change:    what was added or changed, by path
Verified:  the command run and its relevant output, abbreviated
Decision:  what was chosen over what, and why — only when there was a real alternative
```

Rules:

- `Verified` must name a command and its actual result. "Looks correct" is not a verification.
- `Decision` is the part with lasting value. Record rejected alternatives: Deployment vs. StatefulSet,
  exec probe vs. HTTP probe, secretGenerator vs. `kubectl create secret`. Omit the line when the choice
  was obvious.
- Keep an entry under roughly ten lines. If it grows past that, the content belongs in the README or
  in a comment next to the manifest, not in the log.
- Do not log command history, tool calls, or failed attempts that taught nothing.
- Append; never rewrite earlier entries. Corrections are a new entry.

Progress narration in the session stays short: state what is being attempted and what the verification
showed. Do not restate the goal, the plan and the result for every command.

## 13. Working rules

- No plaintext credentials in any committed file.
- No package installation at container runtime.
- Every manifest validated with `kubeconform`.
- Edit files in place; never retype file content from truncated tool output.
- Report what does not work instead of routing around it. No manifest that merely looks operational.
- The README must claim nothing the repository does not deliver.
- Put the reasoning where the reader needs it: a non-obvious value belongs in a comment next to it
  (why this probe command, why this memory limit, why a headless service), not only in the log of §12.

## 14. Definition of done, per stage

Stage 1 is done when, on a **freshly created** cluster:

```
make down && make up
```

completes without error, all pods reach Ready, the publisher Job completes, and the forwarded message
appears in the sink log. Show that output. No commit proposal before that, Stage 0 excepted.

Stage 2 is done when the workflow is green on the remote, not only locally.
