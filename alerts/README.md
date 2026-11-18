# Alert rules (Cockpit / Mimir ruler)

One file = one rule group (Prometheus format, without the top `groups:` list),
pushed by `scripts/push-alert-rules.sh <org>` (the Apply workflow runs it after
`terraform apply`) to the ruler of a Cockpit metrics data source, under the
namespace named after the file. Alerts reach the group's alert manager, which
e-mails `alert_emails` (MAIR-623).

- `group/*.yml`: once per group, to `<org>-probes`: the external probe
  (`probes.yml`) and the group's Argo CD (`argocd.yml`, scraped by the hub
  probe collector of `mairie360/ansible`);
- `instance/*.yml`: once per instance, to `<org>-<env>-metrics`; `__ENV__` is
  replaced by the env name: backups (`backups.yml`) and the instance's health
  (`platform.yml`: disk, memory, crash loops, OOM kills, certificates, 5xx
  rate at Traefik, Postgres connections, silent collector), from the series
  the instance's collector sends (Deploiment `charts/observability`).

`tests/test_alert_rules.py` checks the files and, when `promtool` is
installed, validates them and runs the unit tests of `tests/promtool/` (each
alert fires above its threshold and not under it):

```bash
docker run --rm --entrypoint promtool -v "$PWD:/r" -w /r prom/prometheus:v3.5.0 check rules …
```
