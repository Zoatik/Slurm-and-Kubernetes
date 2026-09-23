#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
report=${DEMO_REPORT:-demo-report.txt}
slurm_folder=demo
slurm_output=/data/$slurm_folder
k8s_compose=(docker compose -f Kubernetes/compose.yaml)

: > "$report"
trap 'code=$?; printf "\nDemo interrupted (line %s, exit code %s).\n" "$LINENO" "$code" >> "$report"' ERR

{
    printf 'DEMO\n'
    printf 'Date: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Common workload: scripts/count_to_1M (Bash counting loop)\n'
    printf 'Clusters remain running after the demo for inspection.\n'
} >> "$report"

printf '1/2 Slurm: starting cluster and submitting job...\n'
if [[ ! -f Slurm/slurm-docker-cluster/Makefile ]]; then
    printf '  Cloning the local Slurm cluster...\n'
    git clone --depth=1 https://github.com/giovtorres/slurm-docker-cluster.git Slurm/slurm-docker-cluster
fi
if [[ ! -f Slurm/slurm-docker-cluster/.env ]]; then
    cp Slurm/slurm-docker-cluster/.env.example Slurm/slurm-docker-cluster/.env
fi
slurm_image=$(docker compose -f Slurm/slurm-docker-cluster/docker-compose.yml config --images \
    | awk '/^slurm-docker-cluster:/ {print; exit}')
if [[ -z $slurm_image ]]; then
    printf '\nSLURM — no cluster image found in the Docker Compose configuration.\n' >> "$report"
    exit 1
fi
if ! docker image inspect "$slurm_image" >/dev/null 2>&1; then
    printf '  Building image %s...\n' "$slurm_image"
    make --no-print-directory slurm-build
fi
make --no-print-directory slurm-up >/dev/null

slurm_ready=false
for ((attempt=0; attempt<90; attempt++)); do
    if docker exec slurmctld sinfo -h -p cpu -o '%t' 2>/dev/null | grep -Eq 'idle|mix|alloc'; then
        slurm_ready=true
        break
    fi
    sleep 2
done
if [[ $slurm_ready != true ]]; then
    printf '\nSLURM — no CPU node became ready within 180 seconds.\n' >> "$report"
    exit 1
fi

slurm_submission=$(make --no-print-directory slurm-submit \
    JOB_SCRIPT=Slurm/job.sh OUT_FOLDER="$slurm_folder" DEPENDENCY=scripts/count_to_1M)
slurm_id=$(printf '%s\n' "$slurm_submission" | awk '$1 == "Submitted" && $2 == "batch" && $3 == "job" {print $4}' | tail -n 1)
if [[ ! $slurm_id =~ ^[0-9]+$ ]]; then
    printf '\nSLURM — could not find a job ID in the sbatch response.\n%s\n' "$slurm_submission" >> "$report"
    exit 1
fi
printf '  Slurm job: %s\n' "$slurm_id"

slurm_record=''
slurm_finished=false
for ((attempt=0; attempt<150; attempt++)); do
    slurm_record=$(docker exec slurmctld sacct -j "$slurm_id" -X -n -P \
        -o JobIDRaw,State,ExitCode,Elapsed,Partition,AllocCPUS,ReqMem,NodeList 2>/dev/null | head -n 1 || true)
    IFS='|' read -r _ slurm_state _ <<< "$slurm_record"
    case "${slurm_state:-}" in
        COMPLETED|FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|BOOT_FAIL|PREEMPTED|DEADLINE)
            slurm_finished=true
            break
            ;;
    esac
    sleep 2
done
if [[ $slurm_finished != true ]]; then
    printf '\nSLURM — job %s did not finish within 300 seconds. Last status: %s\n' \
        "$slurm_id" "$slurm_record" >> "$report"
    exit 1
fi
IFS='|' read -r _ slurm_state slurm_exit slurm_elapsed slurm_partition slurm_cpus slurm_memory slurm_node <<< "$slurm_record"
slurm_tail=$(docker exec slurmctld tail -n 5 "$slurm_output/output_$slurm_id.log" 2>/dev/null || true)
slurm_last=$(printf '%s\n' "$slurm_tail" | awk '/^[0-9]+$/ {last=$0} END {print last}')
{
    printf '\n=== SLURM ===\n'
    printf 'Submission : sbatch Slurm/job.sh ; job %s\n' "$slurm_id"
    printf 'Placement  : partition %s ; node %s\n' "$slurm_partition" "$slurm_node"
    printf 'Resources  : %s allocated CPU(s) ; %s requested memory\n' "$slurm_cpus" "$slurm_memory"
    printf 'Tracking   : state %s ; exit code %s ; elapsed %s\n' "$slurm_state" "$slurm_exit" "$slurm_elapsed"
    printf 'Output     : file %s/output_%s.log\n' "$slurm_output" "$slurm_id"
    printf 'Last number: %s\n' "${slurm_last:-unavailable}"
    printf 'Final output lines:\n%s\n' "${slurm_tail:-unavailable}"
} >> "$report"

printf '2/2 Kubernetes: starting cluster and submitting job...\n'
make --no-print-directory k8s-up >/dev/null
k8s_submission=$(make --no-print-directory k8s-submit)
k8s_name=$(printf '%s\n' "$k8s_submission" | sed -n 's|^job\.batch/\([^[:space:]]*\) created$|\1|p' | tail -n 1)
if [[ -z $k8s_name ]]; then
    printf '\nKUBERNETES — could not find a Job name in the kubectl response.\n%s\n' "$k8s_submission" >> "$report"
    exit 1
fi
printf '  Kubernetes Job: %s\n' "$k8s_name"

k8s_status=''
k8s_finished=false
for ((attempt=0; attempt<150; attempt++)); do
    k8s_status=$("${k8s_compose[@]}" exec -T k3s kubectl get job "$k8s_name" \
        -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}|{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || true)
    case "$k8s_status" in
        True\|*|*\|True)
            k8s_finished=true
            break
            ;;
    esac
    sleep 2
done
if [[ $k8s_finished != true ]]; then
    printf '\nKUBERNETES — Job %s did not finish within 300 seconds. Last status: %s\n' \
        "$k8s_name" "$k8s_status" >> "$report"
    exit 1
fi
if [[ $k8s_status == True\|* ]]; then
    k8s_state=Complete
else
    k8s_state=Failed
fi

k8s_pod=$("${k8s_compose[@]}" exec -T k3s kubectl get pods \
    -l "batch.kubernetes.io/job-name=$k8s_name" \
    -o jsonpath='{.items[0].metadata.name}|{.items[0].spec.nodeName}|{.items[0].spec.containers[0].resources.requests.cpu}|{.items[0].spec.containers[0].resources.requests.memory}|{.items[0].status.phase}|{.items[0].status.containerStatuses[0].state.terminated.exitCode}')
IFS='|' read -r pod_name k8s_node k8s_cpu k8s_memory pod_phase k8s_exit <<< "$k8s_pod"
k8s_tail=$("${k8s_compose[@]}" exec -T k3s kubectl logs "job/$k8s_name" --tail=5 2>/dev/null || true)
k8s_last=$(printf '%s\n' "$k8s_tail" | awk '/^[0-9]+$/ {last=$0} END {print last}')
{
    printf '\n=== KUBERNETES ===\n'
    printf 'Submission : manifest Kubernetes/job.yaml ; Job %s\n' "$k8s_name"
    printf 'Placement  : Pod %s ; node %s\n' "$pod_name" "$k8s_node"
    printf 'Resources  : %s requested CPU ; %s requested memory\n' "$k8s_cpu" "$k8s_memory"
    printf 'Tracking   : Job %s ; Pod %s ; exit code %s\n' "$k8s_state" "$pod_phase" "$k8s_exit"
    printf 'Output     : Pod logs (kubectl logs job/%s)\n' "$k8s_name"
    printf 'Last number: %s\n' "${k8s_last:-unavailable}"
    printf 'Final output lines:\n%s\n' "${k8s_tail:-unavailable}"
} >> "$report"

if [[ $slurm_state == COMPLETED && $k8s_state == Complete && $slurm_last =~ ^[0-9]+$ && $slurm_last == "$k8s_last" ]]; then
    result="both jobs reached $slurm_last successfully"
    demo_ok=true
else
    result='results differ or are incomplete; check the states and outputs above'
    demo_ok=false
fi
printf '\nComparison: %s\n' "$result" >> "$report"

printf 'Report saved to %s\n' "$report"
[[ $demo_ok == true ]]
