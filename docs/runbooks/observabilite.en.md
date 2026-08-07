# Runbook — Observability (Prometheus, Grafana, exporters)

Monitoring stack deployed in Step 7, as Quadlet units like the rest of the stack.

## Components and roles

| Component | Role | Exposure |
|---|---|---|
| Prometheus | Collection and storage of time series (15 days retention) | None — reachable only from the shared network |
| Grafana | Dashboards and alerts | Zero Trust VPN only (no public tunnel route) |
| node_exporter | Host metrics (CPU, memory, disks) + textfile collector | Internal |
| prometheus-podman-exporter | Container metrics via the user Podman socket | Internal |

### Why this container exporter instead of cAdvisor

In rootless mode, cAdvisor has trouble accessing cgroups and consumes a lot of CPU — unacceptable on a dual-core machine. The Podman exporter simply queries the user socket: much lighter and designed for this execution mode.

**Prerequisite**: `systemctl --user enable --now podman.socket`.

## What is monitored, and what is not

- **Backed up**: the Grafana volume (dashboards and configuration — small but the result of hard work).
- **Not backed up, deliberately**: the Prometheus volume. Metric history is *replaceable* data; its loss has no operational consequences and its volume would unnecessarily bloat the archives.

## Monitoring the backup itself

This is the most important addition of this step, drawn directly from the 2026-08-03 and 2026-08-04 incidents (backups silently missing or empty).

`scripts/backup.sh` writes, at each execution, a metrics file in the directory read by the node_exporter *textfile* collector (atomic write: temporary file then rename, so the exporter never reads partial content):

- `homelab_backup_last_run_timestamp_seconds`
- `homelab_backup_last_success_timestamp_seconds`
- `homelab_backup_last_exit_code`

These metrics feed two alerts. The rule on staleness uses **`noDataState: Alerting`**: the complete disappearance of the metric is precisely the symptom we are looking for (script no longer executing at all), so it must trigger the alert rather than being ignored.

## Configuration as code

The data source and alert rules are provisioned from `apps/monitoring/grafana/` (read-only mount in `/etc/grafana/provisioning/`). After a full restore, Grafana recovers its configuration on its own: no mouse-click reconstruction needed.

**Verification after any provisioning change** — an invalid file does not prevent Grafana from starting, the error only appears in the log:
```bash
journalctl --user -u grafana --since "-2m" --no-pager | grep -iE "provision|error|failed"
```

Dashboards remain imported from the interface (community dashboard "Node Exporter Full"); their content lives in the Grafana volume, covered by backups.

## Useful verification queries

```bash
# Are all targets collected?
podman run --rm --network homelab_net docker.io/alpine:3.22 \
  wget -qO- 'http://prometheus:9090/api/v1/query?query=up'

# State of the last backup as seen by Prometheus
podman run --rm --network homelab_net docker.io/alpine:3.22 \
  wget -qO- 'http://prometheus:9090/api/v1/query?query=homelab_backup_last_exit_code'
```

## Notification routing (ntfy)

An alert that no one looks at has no value: rules are routed to a self-hosted notification service, whose contact point and routing policy are also provisioned as code.

**Exposure choice**: this service goes through the public tunnel, unlike the other private services. An alert channel reachable only when the VPN is active would miss precisely the moments when it is useful. Traffic is limited to a few hundred bytes of text.

**Mandatory counterpart**: closed by default access (`deny-all`). Without this, a publicly exposed notification service becomes an open relay usable by anyone.

**Account compartmentalization**:
- an administrator account for clients (phone, browser);
- a separate account for Grafana, **write-only** on the single relevant topic, authenticated by token. Grafana cannot therefore read notifications or write elsewhere.

The token lives in Grafana's environment file and is referenced by `$__env{...}` in the provisioning file: no secret enters the repository.

### Notification formatting

Grafana systematically emits a full JSON body. Published as is, it produces an unreadable notification on a phone.

**First attempt (no effect)**: generic templating per request (`?tpl=yes&t={{.title}}&m={{.message}}`), documented by ntfy but had no effect in practice in this deployment — the notification continued to display raw JSON. Probable cause: curly braces `{{ }}` encoding in the URL, not investigated further.

**Chosen fix**: ntfy's predefined `grafana` template (`?template=grafana`), designed specifically to parse the Grafana webhook payload (title, message, firing/resolved state). ntfy recommends this approach — rather than generic templating — when you control your own server, which is the case here.

**Verification after any contact point change**: send a test notification (**Test** button on the contact point) and confirm that the displayed body is the formatted title/message, not raw JSON — the mere fact that a notification arrives is not enough to validate the formatting.

### End-to-end verification

Use the **Test** button of the contact point in the Grafana interface: this path uses the provisioned token and validates the entire chain without secret manipulation.

Note: a publish launched from the server without credentials returns a refusal (`403`). This is not a failure but proof that the default closure works.

## Resource consumption observed upon deployment

Very low load on the server (a few percent of CPU, about 1.5 GB of memory for the entire stack, system disk occupied at a few percent): comfortable margin for potential additional services.
