# Build log

Append-only decision log. Format and rules: brief §12.

## 2026-09-22 — Stage 0: repository hygiene

Goal:      a clean repository root before any manifest is written.
Change:    `.gitignore` filled (brief §8); `.idea/` and `.claude/settings.local.json` untracked with
           `git rm --cached`; `README.md` skeleton added; this log started.
Verified:  `git ls-files` no longer lists `.idea/*` or `.claude/settings.local.json`;
           `git status --short` clean apart from the intended changes.
Decision:  `.claude/settings.local.json` was tracked and is now untracked. The brief (§8) lists it as
           ignored, and it carries machine-local paths; `.claude/settings.json` stays committable so
           the shared configuration survives.

## 2026-09-22 — Step 0: the four unverified assumptions

Goal:      settle brief §10 before a manifest exists.
Change:    none — verification only. Findings 1–4 plus two side findings reported for decision.
Verified:  1. No `audio-device-repo-server` image. `hub.docker.com/v2/repositories/danzigereduard/`
              returns `count: 3` (forwarder, linuxsoundscanner, kafka-to-rest-api-forwarder);
              four `ghcr.io/collect-sound-devices/*` candidates return `NAME_UNKNOWN`.
           2. `v3.4.3` starts standalone as uid 1654 against `rabbitmq:3.13-management`; the log line
              "Consumer service parameters initialized" echoed every value passed as `RabbitMQ__*`,
              `ApiBaseUrl__*`. Success path: sink received `POST /api/AudioDevices/ok`, forwarder logged
              "Message processed successfully on attempt 1". Failure path with `MaxRetryAttempts=3`,
              `RetryDelayInSeconds=5`: attempts 1→2→3 five seconds apart, then "Routed to failed queue";
              `list_queues` ended at `sdr_queue.failed 1`.
           3. No HTTP endpoint. `netstat -ltn` in the running container lists only Docker's resolver
              socket; `Program.cs` uses `Host.CreateDefaultBuilder`, not `WebApplication`.
           4. Payload is a flat JSON object with `httpRequest`, `urlSuffix`, `deviceMessageType`,
              `updateDate`; the request URL is `ApiBaseUrl:<Target>` + `urlSuffix`, and the echo-server
              body shows the whole object is forwarded, `httpRequest`/`urlSuffix` included.
Decision:  deferred — all six points are the user's call.

## 2026-09-22 — Step 0 finding 1 settled: the sink

Goal:      pick the REST sink now that no `audio-device-repo-server` image exists.
Change:    none yet; binds Stage 1 to `ealen/echo-server:0.9.2` and an in-cluster Service.
Verified:  `GET` on the configured Codespace endpoint returned HTTP 404 with an empty body;
           the forwarder README links a source repo for the real server, but no registry publishes it.
Decision:  in-cluster echo-server over the Codespace-hosted real API, which the user confirms is the
           only place that API runs. Three reasons: with `ApiBaseUrl:Target=Codespace` every failed
           delivery calls `GitHubCodespaceAwaker`, which POSTs to a third-party vercel endpoint — and
           brief §6 makes deliberate failure the demo; a codespace bound to one account cannot satisfy
           §1 "clean machine, one command" or §14 "green on the remote"; and a real API cannot be made
           to fail on demand, whereas echo-server's `?echo_code=500` can. The Codespace target stays
           reachable as an env-var override documented in the README and marked unexercised.

## 2026-09-22 — Step 0 finding 2 settled: brief §6 corrected in place

Goal:      stop the wrong configuration keys from reaching the manifests.
Change:    `claude/initial-prompt-info.md` §6 — `RabbitMqMessageDeliverySettings:*` replaced by
           `RabbitMQ:MessageDelivery:*`, with the three resulting `__` environment variables spelled
           out and a note on where the wrong name came from.
Verified:  `Program.cs` binds `config.GetSection("RabbitMQ:MessageDelivery")`; `v3.4.3` echoed
           `MaxRetryAttempts 3 RetryDelaySeconds 5` after being passed the corrected variables.
Decision:  corrected the brief rather than documenting the discrepancy in the README, on the user's
           instruction. This is a deliberate exception to Stage 0's "do not modify this brief": a
           reader who follows the old names gets a forwarder that silently keeps its built-in defaults.
           The forwarder's own README is upstream and stays wrong; only this repository is corrected.

## 2026-09-22 — Step 0 findings 3 and 5 settled: probes and the retry-TTL trap

Goal:      close the last two Step 0 questions so Stage 1 can be written.
Change:    none yet; binds Stage 1 to exec probes on the forwarder and a per-overlay `QueueName`.
Verified:  the forwarder opens no listening socket (`netstat -ltn` shows only Docker's resolver), so
           an HTTP probe is impossible. `netstat -tn | grep -q ':5672.*ESTABLISHED'` returned 0 on a
           working container and 1 on one stuck in its connect-retry loop, so it discriminates.
           The trap itself: a forwarder declaring `sdr_queue.retry` with a different
           `RetryDelayInSeconds` than the existing durable queue gets
           `PRECONDITION_FAILED - inequivalent arg 'x-message-ttl' ... received '12000' but current is
           '5000'` and retries forever.
Decision:  probes — readiness is the AMQP-connection check above, liveness is
           `pgrep -f RmqToRestApiForwarder.dll`. Two different checks as §7 requires, and liveness
           deliberately does not restart a pod that is merely waiting for the broker.
           TTL — each overlay gets its own `QueueName` rather than identical retry delays everywhere or
           a PVC wiped by `make down`. The alternatives either forbid the overlays from differing in
           the setting the demo is about, or make §7's persistence claim untestable.

## 2026-09-22 — Stage 1: manifests written and statically validated

Goal:      the core chain as manifests: namespace, config, secret, broker, forwarder, sink, publisher.
Change:    `base/` (namespace, configmap, secret.example, rabbitmq, sink, forwarder, publisher,
           kustomization), `overlays/dev/`, `kind/kind-config.yaml`, `Makefile`, `scripts/up.sh`,
           `scripts/verify.sh`.
Verified:  `make verify` — kubeconform "8 resources found parsing stdin - Valid: 8, Invalid: 0,
           Errors: 0"; kube-score clean on all six scored objects with two suppressions, leaving one
           WARNING (sink single replica).
           NOT verified: `make up` has not been run. The command was refused by the sandbox, so the
           §14 acceptance test — pods Ready, publisher complete, message in the sink log — is
           outstanding. Stage 1 is not done.
Decision:  two kube-score criticals were fixed rather than suppressed, against the earlier plan to
           suppress four checks. `readOnlyRootFilesystem` and uids above 10000 both turned out to work
           for every container once the broker got emptyDirs on `/etc/rabbitmq/conf.d`,
           `/var/log/rabbitmq` and `/tmp` — confirmed under `docker run --read-only --user 10999`,
           management plugin still enabled, `rabbitmq-diagnostics status` OK after 7s. The mount is on
           `conf.d` rather than `/etc/rabbitmq` because the latter holds `enabled_plugins`.
           Only `pod-networkpolicy` (§9) and `container-image-pull-policy` (§7 mandates IfNotPresent)
           remain suppressed. §9 also predicted a PodDisruptionBudget warning; kube-score v1.20.0 does
           not emit one for single-replica workloads, so no suppression was needed for it.
