K8S_COMPOSE := docker compose -f Kubernetes/compose.yaml

.PHONY: slurm-up slurm-down slurm-shell slurm-jobs slurm-submit k8s-up k8s-down k8s-submit k8s-jobs k8s-logs

slurm-build:
	@echo "Building Slurm Docker images..."
	# command is make build from the slurm directory
	$(MAKE) -C "Slurm/slurm-docker-cluster" build

slurm-up:
	@echo "Starting Slurm services..."
	# command is make up from the slurm directory
	$(MAKE) -C "Slurm/slurm-docker-cluster" up

slurm-down:
	@echo "Stopping Slurm services..."
	# command is make down from the slurm directory
	$(MAKE) -C "Slurm/slurm-docker-cluster" down

slurm-shell:
	@echo "Starting Slurm shell..."
	# command is make shell from the slurm directory
	$(MAKE) -C "Slurm/slurm-docker-cluster" shell

slurm-jobs:
	@echo "Listing Slurm jobs..."
	# command is make jobs from the slurm directory
	$(MAKE) -C "Slurm/slurm-docker-cluster" jobs

slurm-submit:
	@echo "Submitting Slurm job..."
	@set -e; \
	if [ -z "$(JOB_SCRIPT)" ]; then \
		echo "Error: No job script provided. Set the JOB_SCRIPT variable."; \
		exit 1; \
	fi; \
	if [ -z "$(OUT_FOLDER)" ]; then \
		echo "Error: No output folder provided. Set the OUT_FOLDER variable."; \
		exit 1; \
	fi; \
	OUT_PATH="/data/$(OUT_FOLDER)"; \
	docker exec slurmctld mkdir -p "$$OUT_PATH"; \
	if [ -z "$(DEPENDENCY)" ]; then \
		echo "No dependency provided. Set the OUT_FOLDER variable if needed."; \
	else \
		echo "Dependency provided: $(DEPENDENCY)"; \
		for dependency in $(DEPENDENCY); do \
			docker cp "$$dependency" "slurmctld:$$OUT_PATH/$$(basename "$$dependency")"; \
		done; \
	fi; \
	JOB_SCRIPT_NAME="$(notdir $(JOB_SCRIPT))"; \
	JOB_SLURM_PATH="$$OUT_PATH/$$JOB_SCRIPT_NAME"; \
	docker cp "$(JOB_SCRIPT)" "slurmctld:$$JOB_SLURM_PATH"; \
	docker exec slurmctld sbatch \
		--chdir="$$OUT_PATH" \
		--output="$$OUT_PATH/output_%j.log" \
		--error="$$OUT_PATH/error_%j.log" \
		"$$JOB_SLURM_PATH"

k8s-up:
	$(K8S_COMPOSE) up -d --wait
	$(K8S_COMPOSE) exec -T k3s kubectl wait --for=condition=Ready node/k3s-demo --timeout=180s

k8s-down:
	$(K8S_COMPOSE) down

k8s-submit:
	$(K8S_COMPOSE) exec -T k3s kubectl create configmap count-script --from-file=count_to_1M=/demo/scripts/count_to_1M --dry-run=client -o yaml | $(K8S_COMPOSE) exec -T k3s kubectl apply -f -
	$(K8S_COMPOSE) exec -T k3s kubectl create -f /demo/Kubernetes/job.yaml

k8s-jobs:
	$(K8S_COMPOSE) exec -T k3s kubectl get jobs,pods -l app=count-to-1m

k8s-logs:
	@test -n "$(JOB)" || { echo "Usage: make k8s-logs JOB=count-to-1m-xxxxx"; exit 1; }
	$(K8S_COMPOSE) exec -T k3s kubectl logs job/$(JOB) --tail=10
