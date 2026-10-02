# test-platform

A self-contained Kubernetes demo: a publisher sends messages through RabbitMQ to a .NET forwarder,
which posts them to a REST sink. It exists to show operational practice — namespaces, probes, resource
limits, secrets, a stateful broker with persistent storage, and retry / dead-letter handling — not to
show an application.

**Not for production.** Single-replica workloads, a local kind cluster, no network isolation.

> **Status: Stage 1 written, not yet accepted.** The manifests, the `Makefile` and the scripts exist
> and pass static validation (`make verify`). The acceptance run — `make down && make up` on a fresh
> cluster, publisher complete, message in the sink log — has not passed yet. Sections marked
> _(pending)_ describe what will be there, and are not a claim that it works today.

## Architecture

    publisher (Job) → RabbitMQ (StatefulSet + PVC) → RmqToRestApiForwarder → REST sink

Everything runs in the namespace `test-platform` on a kind cluster with one control-plane and two
workers. Components and images:

| Component | Kind | Image |
|---|---|---|
| Broker | StatefulSet + headless Service, 1 Gi PVC | `rabbitmq:3.13-management` |
| Forwarder | Deployment, no Service | `danzigereduard/rmq-to-rest-api-forwarder:v3.4.3` |
| REST sink | Deployment + Service | `ealen/echo-server:0.9.2` |
| Publisher | Job, uses `rabbitmqadmin` | `rabbitmq:3.13-management` |

No image is built here. The sink is `echo-server` because no public image of the real
`audio-device-repo-server` exists. Configuration is in `base/configmap.yaml`; the broker credentials
are a Secret created at deploy time (`base/secret.example.yaml` lists the keys).

## Quick start

Prerequisites: Docker, kind, kubectl, make, openssl.

```bash
make up       # create the cluster, create the Secret, apply overlays/dev, wait for readiness
make down     # delete the cluster, including the broker volume
```

Other targets:

| Target | Does |
|---|---|
| `make verify` | static validation: kubeconform and kube-score, run as pinned containers |
| `make demo` | re-run the publisher and show the forwarder and sink logs |
| `make logs` | follow the forwarder log |
| `make ui` | print the broker credentials and port-forward the management UI to `localhost:15672` |

## Demo: delivery, retry, dead-letter

_(pending — Stage 3)_

1. Sink returns success — the message is delivered and appears in the sink log.
2. Sink returns an error — the message moves to the `.retry` queue and is redelivered after the TTL.
3. Retries are exhausted — the message lands in the `.failed` queue.

`make demo` covers step 1 only. Steps 2 and 3 arrive with `scripts/demo-retry.sh`.

## Why the forwarder has exec probes

The forwarder serves no HTTP. It is a generic .NET host (`Host.CreateDefaultBuilder`, not
`WebApplication`), and `netstat -ltn` in a running container shows no listening socket. An HTTP probe
is therefore impossible. Both probes are exec checks instead; what each one tests is commented in
`base/forwarder.yaml`.

## Changing the retry delay

`RabbitMQ__MessageDelivery__RetryDelayInSeconds` is written into the durable `<QueueName>.retry`
queue as `x-message-ttl` when the forwarder first declares it. The broker volume keeps that queue. A
forwarder started later with a different delay fails with `PRECONDITION_FAILED - inequivalent arg
'x-message-ttl'` and retries forever. To change the delay, either change `QUEUE_NAME` in the same
step, or run `make down` first, which deletes the volume and the queue with it.

## Limits

- No NetworkPolicy: kindnet does not enforce it, so the manifest would have no effect.
- `ApiBaseUrl__Target` is `Local`, the in-cluster sink. The forwarder's `Codespace` target, which
  calls the real API, is not exercised here.
- kind needs a host with cgroup v2. On cgroup v1 the kubelet of the Kubernetes v1.37.0 node image
  (kind v0.33.0's default) refuses to start (`failCgroupV1: true`).

## Tested tool versions

_(pending — filled in once the acceptance run has passed)_

## Build brief

The scope, stages and acceptance criteria for this repository live in
[claude/initial-prompt-info.md](claude/initial-prompt-info.md). Decisions taken along the way are
recorded in [claude/build-log.md](claude/build-log.md).

## Licence

MIT — see [LICENSE](LICENSE).
