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
