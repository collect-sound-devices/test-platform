# test-platform

A self-contained Kubernetes demo: a publisher sends messages through RabbitMQ to a .NET forwarder,
which posts them to a REST sink. It exists to show operational practice — namespaces, probes, resource
limits, secrets, a stateful broker with persistent storage, and retry / dead-letter handling — not to
show an application.

**Not for production.** Single-replica workloads, a local kind cluster, no network isolation.

> **Status: skeleton.** Nothing below is implemented yet. Stage 0 (repository hygiene) is complete;
> the manifests, the `Makefile` and the scripts arrive in Stage 1 and later. Sections marked _(pending)_
> describe what will be there, and are not a claim that it works today.

## Architecture

_(pending — Stage 1)_

    publisher (Job) → RabbitMQ (StatefulSet + PVC) → RmqToRestApiForwarder → REST sink

## Quick start

_(pending — Stage 1)_

## Demo: delivery, retry, dead-letter

_(pending — Stage 3)_

1. Sink returns success — the message is delivered and appears in the sink log.
2. Sink returns an error — the message moves to the `.retry` queue and is redelivered after the TTL.
3. Retries are exhausted — the message lands in the `.failed` queue.

## Limits

_(pending)_

## Tested tool versions

_(pending — filled in once Stage 1 has actually been run)_

## Build brief

The scope, stages and acceptance criteria for this repository live in
[claude/initial-prompt-info.md](claude/initial-prompt-info.md). Decisions taken along the way are
recorded in [claude/build-log.md](claude/build-log.md).

## Licence

MIT — see [LICENSE](LICENSE).
