# Desktop Resource Monitoring

A small telemetry stack for host and device resource monitoring.

collectd collects CPU, memory, disk, network, process, sensor, thermal, uptime, user, and optional NVIDIA GPU metrics. The collectd `write_prometheus` plugin exposes those metrics on port `9103`; VictoriaMetrics scrapes that endpoint and stores the time series; Grafana provisions the datasource and the included monitoring dashboard automatically.

## Repository Layout

```text
.
|-- compose.yaml
|-- config/
|   |-- collectd/
|   |   |-- collectd.conf
|   |   `-- scripts/collectd-nvidia.sh
|   `-- prometheus/prometheus.yml
|-- grafana/
|   |-- dashboards/monitoring.json
|   `-- provisioning/
|       |-- dashboards/dashboards.yml
|       `-- datasources/victoriametrics.yml
`-- systemd/desktop-resource-monitoring.service
```

## Prerequisites

- Docker with the Compose plugin.
- collectd on every machine or embedded device you want to monitor.
- collectd plugins: `cpu`, `df`, `disk`, `entropy`, `exec`, `interface`, `irq`, `load`, `memory`, `processes`, `sensors`, `swap`, `thermal`, `uptime`, `users`, and `write_prometheus`.
- Optional: `nvidia-smi` for NVIDIA GPU metrics.

On Debian or Ubuntu hosts, collectd can usually be installed with:

```bash
sudo apt update
sudo apt install -y collectd lm-sensors
```

## Quickstart

1. Clone the repository and enter it.

```bash
git clone <repo-url> desktop-resource-monitoring
cd desktop-resource-monitoring
```

2. Optional: set Grafana credentials before the first start.

```bash
cp .env.example .env
$EDITOR .env
```

If you skip this step, Grafana starts with `admin` / `admin` for a new data volume.

3. Start VictoriaMetrics and Grafana.

```bash
docker compose up -d
```

4. Install the collectd configuration on the monitored host.

```bash
sudo install -d /etc/collectd/scripts
sudo install -m 0644 config/collectd/collectd.conf /etc/collectd/collectd.conf
sudo install -m 0755 config/collectd/scripts/collectd-nvidia.sh /etc/collectd/scripts/collectd-nvidia.sh
sudo systemctl restart collectd
```

5. Check that data is flowing.

```bash
curl http://localhost:9103/metrics | head
curl http://localhost:8428/-/ready
```

6. Open Grafana at http://localhost:3000.

The VictoriaMetrics datasource and the `Monitoring` dashboard are provisioned automatically. The dashboard uses the `Device` variable to switch between collectd hostnames.

## Monitoring Remote Devices

Run collectd on each host or embedded device, make sure its `write_prometheus` endpoint is reachable from the Docker host, and give each device a unique `Hostname` in its collectd config.

Then add the device to `config/prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: collectd-devices
    static_configs:
      - targets:
          - host.docker.internal:9103
          - 192.168.1.50:9103
          - embedded-device.local:9103
```

Apply scrape target changes with:

```bash
docker compose restart victoriametrics
```

## Sharing VictoriaMetrics Data

VictoriaMetrics stores its database in the Docker volume mounted at `/victoria-metrics-data`. 

The default volume name is `desktop-resource-monitoring_victoria-metrics-data` when you follow the quickstart directory name. If you use a different Compose project name or clone path, find the actual volume name with:

```bash
docker volume ls --format '{{.Name}}' | grep 'victoria-metrics-data$'
```

Use that value for `VM_VOLUME` in the commands below if it differs from the default.

### Export a Full Database Archive

Stop VictoriaMetrics first so the archive is consistent, then package the volume:

```bash
mkdir -p exports
VM_VOLUME=desktop-resource-monitoring_victoria-metrics-data

docker compose stop victoriametrics
docker run --rm \
  -v "$VM_VOLUME:/data:ro" \
  -v "$PWD/exports:/exports" \
  alpine sh -c 'tar -czf "/exports/victoria-metrics-$(date +%Y%m%d-%H%M%S).tar.gz" -C /data .'
docker compose start victoriametrics
```

Share the generated `exports/victoria-metrics-*.tar.gz` file with a colleague. They can restore it into their own stack with the import steps below.

### Import a Shared Database Archive

Importing replaces the local VictoriaMetrics database. Copy the archive into `imports/victoria-metrics-data.tar.gz`, stop the stack, recreate the volume, unpack the archive, and start again:

```bash
mkdir -p imports
cp /path/to/victoria-metrics-archive.tar.gz imports/victoria-metrics-data.tar.gz
VM_VOLUME=desktop-resource-monitoring_victoria-metrics-data

docker compose down
docker volume rm "$VM_VOLUME" 2>/dev/null || true
docker volume create "$VM_VOLUME"
docker run --rm \
  -v "$VM_VOLUME:/data" \
  -v "$PWD/imports:/imports:ro" \
  alpine sh -c 'tar -xzf /imports/victoria-metrics-data.tar.gz -C /data'
docker compose up -d
```

Open Grafana after the import and use the existing `Monitoring` dashboard. The dashboard is part of the repository, so only the VictoriaMetrics archive is needed for the collected time-series data. If you also need Grafana UI state that was changed outside the repository, export and import the `desktop-resource-monitoring_grafana-data` volume the same way.

For smaller analysis handoffs, you can also export selected time series through the VictoriaMetrics HTTP API instead of sharing the whole database volume.

## Optional Systemd Service

The unit in `systemd/desktop-resource-monitoring.service` starts and stops the Docker Compose stack. It assumes the repository is installed at `/opt/desktop-resource-monitoring`.

```bash
sudo mkdir -p /opt
sudo cp -a . /opt/desktop-resource-monitoring
sudo install -m 0644 systemd/desktop-resource-monitoring.service /etc/systemd/system/desktop-resource-monitoring.service
sudo systemctl daemon-reload
sudo systemctl enable --now desktop-resource-monitoring.service
```

If you keep the repository somewhere else, edit `WorkingDirectory` in the service file before installing it.

## Ports

| Service | Port | Purpose |
| --- | ---: | --- |
| collectd `write_prometheus` | 9103 | Metrics endpoint scraped by VictoriaMetrics |
| VictoriaMetrics | 8428 | Time-series database and Prometheus-compatible API |
| Grafana | 3000 | Dashboard UI |

## Notes

- Docker data is stored in named volumes: `desktop-resource-monitoring_grafana-data` and `desktop-resource-monitoring_victoria-metrics-data`.
- The NVIDIA collectd script stays idle if `nvidia-smi` is not available. Remove `LoadPlugin exec` and the `<Plugin exec>` block from `config/collectd/collectd.conf` if you do not want the optional GPU collector at all.
- If Grafana has no data, first check `http://localhost:9103/metrics`, then `http://localhost:8428/targets`, then the target list in `config/prometheus/prometheus.yml`.
