# Slurm and Kubernetes
Demo repository for comparing Slurm and Kubernetes usage.

## Setup
### Slurm (based on https://tomsing1.github.io/blog/posts/slurm_docker_cluster/)
1. Clone the repo : 
```bash
git clone --depth=1 https://github.com/giovtorres/slurm-docker-cluster.git
cd slurm-docker-cluster
```
2. Setup env :
```bash
cp .env.example .env
```

3. Build the image :
```bash
make build
````

4. Start / Test / Stop the cluster :
```bash
make up
make test
make down
```

