##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk command is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build

build-images: docker ## Build the app images
	@for dir in apps/*/; do \
		if [ -f "$${dir}Dockerfile" ]; then \
			app_name=$$(basename "$$dir"); \
			echo "Building app image: $$app_name"; \
			docker build -t "demo-$$app_name" "$$dir"; \
		fi; \
	done

ensure-images: docker ## Ensure all app images exist, build them if not
	@for dir in apps/*/; do \
		if [ -f "$${dir}Dockerfile" ]; then \
			app_name=$$(basename "$$dir"); \
			image_name="demo-$$app_name"; \
			if [ -z "$$(docker images -q $$image_name)" ]; then \
				echo "Building app image: $$app_name"; \
				docker build -t "$$image_name" "$$dir"; \
			else \
				echo "Image $$image_name already exists"; \
			fi; \
		fi; \
	done

build-node: docker ## Build the docker node image used to bootstrap KinD cluster
	docker build -t demo-kind-node:latest .

build: build-images ## Build the necessary resources for the environment

##@ Environment

cluster: kind ## Create the KinD cluster to run demo scenarios
	@kind get clusters | grep -qw "^demo$$" || kind create cluster --config kind-config.yaml --name demo

cert-manager: ## Install cert-manager on the KinD cluster
	@echo "Installing cert-manager..." && \
	(helm repo list | grep -qw "jetstack" || \
		(helm repo add jetstack https://charts.jetstack.io && helm repo update)) && \
	(kubectl get namespaces | grep -qw "cert-manager" || \
		helm install \
		cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--create-namespace \
		--set installCRDs=true)

upload-images: kind ## Upload app images into the cluster
	@for dir in apps/*/; do \
		if [ -f "$${dir}Dockerfile" ]; then \
			app_name=$$(basename "$$dir"); \
			kind load docker-image "demo-$${app_name}:latest" --name demo; \
		fi; \
	done

up: ensure-deps ensure-images cluster cert-manager upload-images ## Bring up the demo environment

down: ## Teardown the demo environment
	kind delete cluster --name demo

##@ Apps

simple: up ## Deploy the "simple" app for curl'ing external APIs
	kubectl apply -f apps/simple/deployment.yaml

artillery: up ## Deploy the "artillery" app for hammering multiple APIs
	kubectl apply -f apps/artillery/deployment.yaml

datadog: up ## Deploy the "datadog" app for reporting to datadog
	helm install datadog-agent -f apps/datadog/values.yaml datadog/datadog -n datadog

##@ Demo

describe: ## Describe the app pod
	@kubectl describe pod/$$(kubectl get pods -l app=app -o jsonpath="{.items[0].metadata.name}")

exec: ## Exec into the app container
	@kubectl exec -it $$(kubectl get pods -l app=app -o jsonpath="{.items[0].metadata.name}") -- /bin/sh

restart: ## Rollout a restart on the deployment
	kubectl rollout restart deployment/app-deployment && \
	kubectl rollout status deployment/app-deployment

init-logs: ## Show the qpoint-init logs
	@kubectl logs $$(kubectl get pods -l app=app -o jsonpath="{.items[0].metadata.name}") -c qtap-init

gateway-proxy: ## Establish a port forward proxy
	@kubectl port-forward -n qpoint $$(kubectl get pods -l app.kubernetes.io/name=qtap -o jsonpath="{.items[0].metadata.name}" -n qpoint) 9901:9901

gateway-logs: ## Stream the gateway logs
	@kubectl logs -f -n qpoint pod/$$(kubectl get pods -l app.kubernetes.io/name=qtap -o jsonpath="{.items[0].metadata.name}" -n qpoint)

operator-logs: ## Stream the operator logs
	@kubectl logs -f -n qpoint pod/$$(kubectl get pods -l app.kubernetes.io/name=qtap-operator -o jsonpath="{.items[0].metadata.name}" -n qpoint)

##@ Dependencies

docker: ## Ensure docker is installed and running
	@docker info > /dev/null 2>&1 || (echo "Error: Docker must be installed and running" && exit 1 )

kubectl: ## Ensure kubectl is installed
	@which kubectl > /dev/null 2>&1 || (echo "Error: Kubectl must be installed" && exit 1)

kind: ## Ensure kind is installed
	@which kind > /dev/null 2>&1 || (echo "Error: KinD must be installed" && exit 1)

helm: ## Ensure helm is installed
	@which kind > /dev/null 2>&1 || (echo "Error: Helm must be installed" && exit 1)

ensure-deps: docker kubectl kind helm ## Ensure all dependencies are ready
