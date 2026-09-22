CLUSTER   ?= test-platform
NAMESPACE ?= test-platform
OVERLAY   ?= overlays/dev

.PHONY: up down demo verify logs ui

## up: create the cluster, create the Secret, apply the overlay, wait for readiness
up:
	@CLUSTER=$(CLUSTER) NAMESPACE=$(NAMESPACE) OVERLAY=$(OVERLAY) ./scripts/up.sh

## down: delete the cluster, and with it every volume it held
down:
	@kind delete cluster --name $(CLUSTER)

## verify: static validation only — no cluster required
verify:
	@OVERLAY=$(OVERLAY) ./scripts/verify.sh

## demo: re-run the publisher against a running cluster and show what reached the sink
demo:
	@kubectl -n $(NAMESPACE) delete job publisher --ignore-not-found
	@kubectl apply -k $(OVERLAY)
	@kubectl -n $(NAMESPACE) wait --for=condition=complete job/publisher --timeout=120s
	@echo "--- forwarder ---"
	@kubectl -n $(NAMESPACE) logs deployment/forwarder --tail=20
	@echo "--- sink ---"
	@kubectl -n $(NAMESPACE) logs deployment/sink --tail=5

## logs: tail the forwarder, which is where delivery and retry decisions are logged
logs:
	@kubectl -n $(NAMESPACE) logs -f deployment/forwarder

## ui: port-forward the RabbitMQ management UI to http://localhost:15672
ui:
	@echo "RabbitMQ management UI: http://localhost:15672"
	@echo "user: $$(kubectl -n $(NAMESPACE) get secret rabbitmq-credentials -o jsonpath='{.data.username}' | base64 -d)"
	@echo "pass: $$(kubectl -n $(NAMESPACE) get secret rabbitmq-credentials -o jsonpath='{.data.password}' | base64 -d)"
	@kubectl -n $(NAMESPACE) port-forward svc/rabbitmq 15672:15672
