# mini-action-time

Minimal, ephemeral self-hosted GitHub Actions runner image for any Docker host.

- Only third-party code: GitHub's official `ghcr.io/actions/actions-runner`, pinned by digest.
- One job per container: register, run one job, exit. Restart policy `always` brings up a fresh one.
- Registers to **one** private repo using a fine-grained PAT.
- The PAT never reaches workflow jobs: `entrypoint.sh` trades it for a short-lived registration token, `unset`s it, then `exec`s the runner with a clean environment. The runner's `env.sh` only writes a fixed allowlist (`LANG`, `JAVA_HOME`, …) to `.env`, so the PAT cannot land there either.
- `sudo` is removed, so jobs cannot install or change anything at runtime.

## 1. Create the fine-grained PAT

1. GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate new token.
2. **Expiration:** ~90 days. Put a calendar reminder a week before expiry to rotate it.
3. **Repository access:** *Only select repositories* → pick the single repo the runner serves.
4. **Repository permissions:** **Administration: Read and write**. Nothing else.
5. Generate and copy it. It goes into the container's `GH_PAT` variable.

**Rotating:** generate a new token, update `GH_PAT` on each runner container, recreate the containers, then revoke the old token.

## 2. Build the image

On the Docker host:

```bash
# Private repo: authenticate with a separate read-only credential (deploy key or Contents: read PAT), not the runner PAT
git clone https://github.com/<owner>/mini-action-time.git
cd mini-action-time
docker build -t mini-action-time:local .
```

To update later: review and merge the Dependabot PR, then `git pull && docker build -t mini-action-time:local .` and **recreate** each runner container. A restart, including the `always` restart after each job, reuses the container's original image, so without recreating the runners keep running the old image. Clean up afterwards with `docker image prune`.

## 3. Run a runner

```bash
docker run -d --name runner-1 \
  --restart=always \
  --network <isolated-network> --ip <runner-1-ip> \
  --dns <public-resolver> \
  -e GH_OWNER=<owner> \
  -e GH_REPO=<repo> \
  -e GH_PAT=<fine-grained-pat> \
  -e RUNNER_NAME=runner-1 \
  mini-action-time:local
```

| Variable | Required | Default |
|---|---|---|
| `GH_OWNER` | yes | |
| `GH_REPO` | yes | |
| `GH_PAT` | yes | |
| `RUNNER_NAME` | no | `runner-<hostname>` |
| `RUNNER_LABELS` | no | `ephemeral` |

Put the container on a network isolated from the rest of your LAN, such as its own VLAN or subnet with firewall rules allowing only outbound internet.

**Do NOT add:**
- any `/var/run/docker.sock` mount (that is root on the host),
- any host directory or volume mounts.

## 4. A second runner for parallel jobs

Run the same command again with a different container name, IP and `RUNNER_NAME` (e.g. `runner-2`, `<runner-2-ip>`). Same `GH_OWNER`, `GH_REPO`, `GH_PAT`, labels.

## 5. Using it in workflows

```yaml
jobs:
  build:
    runs-on: [self-hosted, ephemeral]
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@<full-commit-sha> # vX.Y.Z
```

## 6. Isolation tests

From inside the container (`docker exec -it runner-1 bash`):

```bash
# Should succeed (HTTP response headers)
curl -I https://github.com

# Should all FAIL (timeout / refused)
curl -m 5 http://<docker-host-lan-ip>
curl -m 5 http://<router-lan-ip>        # the router's main LAN address, not the isolated network's gateway
curl -m 5 http://<other-lan-service-ip>:<port>
```

The image doesn't ship `ping`. Add `iputils-ping` in the toolchain section if you want ICMP checks too; the TCP checks above matter more, since firewalls can block ICMP while TCP gets through. If any of the "should fail" checks succeed, fix the firewall rules before running jobs.

With a macvlan network, the Docker host and its containers can't talk to each other by default, but don't rely on that alone; block it in the firewall too.

## 7. Security notes

- **Pin third-party actions to full commit SHAs**, not tags (`uses: owner/action@<40-char sha> # v1.2.3`). Tags can be moved.
- **Keep `permissions:` minimal** in every workflow. Set a top-level `permissions: {}` or `contents: read`, and grant more per job only where needed.
- **Set spend limits on any paid API keys** used by workflows, and give the runner its own keys so they can be revoked independently.
- **Rebuild only after reviewing Dependabot PRs.** Check the runner release notes and that the new digest comes from `ghcr.io/actions/actions-runner`.
- Only run workflows from trusted code. Don't trigger this runner from `pull_request_target` or from forks.
- The runner's own credentials (`.runner`, `.credentials`) are readable by the job, as on any self-hosted runner. `--ephemeral` makes them single-use, and the container is discarded after each job.
- `GH_PAT` stays visible in `docker inspect` and in the container config on the host. Treat host access as PAT access.
