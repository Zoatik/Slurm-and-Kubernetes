# Slurm and Kubernetes

Run the same `scripts/count_to_1M` batch workload with Slurm and Kubernetes, then compare how each system submits, schedules, and reports a job.

## Slurm

The Slurm demo uses the upstream [slurm-docker-cluster](https://github.com/giovtorres/slurm-docker-cluster) checkout. 

From the root of this repository:

```sh
git clone --depth=1 https://github.com/giovtorres/slurm-docker-cluster.git Slurm/slurm-docker-cluster
cp Slurm/slurm-docker-cluster/.env.example Slurm/slurm-docker-cluster/.env
make slurm-build
make slurm-up
make slurm-submit JOB_SCRIPT=Slurm/job.sh OUT_FOLDER=results DEPENDENCY=scripts/count_to_1M
make slurm-jobs
```

`make slurm-shell` opens a shell in the controller to inspect the job and its output under /data/results. Stop the cluster with `make slurm-down`.

## Kubernetes

`Kubernetes/compose.yaml` runs a single-node k3s cluster in a Docker container.

Run these commands from the root of the repository:

```sh
make k8s-up
make k8s-submit
make k8s-jobs
```

`make k8s-submit` prints a unique Job name such as `count-to-1m-abcde`. \
Use `make k8s-jobs` to check when it reaches `Complete`, then substitute that name below to inspect the final log lines and stop the cluster:

```sh
make k8s-logs JOB=count-to-1m-abcde
make k8s-down
```

Each `make k8s-submit` refreshes the ConfigMap from `scripts/count_to_1M` and creates a new Job. `make k8s-down` removes the local demo cluster and its jobs.

