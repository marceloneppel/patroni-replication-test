.PHONY: patroni pebble

dependencies:
	sudo apt-get update
	sudo apt-get install -y curl gettext-base
	sudo snap install --classic microk8s
	sudo adduser ${USER} microk8s
	sudo microk8s status --wait-ready
	sudo microk8s enable storage dns ingress
	sudo snap alias microk8s.kubectl kubectl

clean:
	kubectl delete -f k8s.yaml
	kubectl delete service/patronidemo-config

build:
	docker build -t test-patroni patroni
	docker build -t test-pebble pebble
	docker save test-patroni | microk8s ctr images import -
	docker save test-pebble | microk8s ctr images import -	

patroni:
	IMAGE=test-patroni envsubst < k8s.yaml | kubectl apply -f -

pebble:
	IMAGE=test-pebble envsubst < k8s.yaml | kubectl apply -f -

crash-leader:
	for n in $$(seq 0 2); do \
		ip=$$(kubectl get pod patronidemo-$$n -o custom-columns=ip:.status.podIP); \
		status=$$(curl -s -w "\n%{http_code}\n" $$ip:8008 |sed -n '4 p'); \
		if [ $$status = 200 ]; then \
			kubectl delete pod/patronidemo-$$n; \
			break; \
		fi \
	done

logs:
	kubectl exec pod/patronidemo-0 -- tail -2 patroni.log
	@echo ""
	kubectl exec pod/patronidemo-1 -- tail -2 patroni.log
	@echo ""
	kubectl exec pod/patronidemo-2 -- tail -2 patroni.log

zombies:
	kubectl exec pod/patronidemo-0 -- ps aux | grep defunct || true
	@echo ""
	kubectl exec pod/patronidemo-1 -- ps aux | grep defunct || true
	@echo ""
	kubectl exec pod/patronidemo-2 -- ps aux | grep defunct || true