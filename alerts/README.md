# Alert rules (Cockpit / Mimir ruler)

One file = one rule group (Prometheus format, without the top `groups:` list),
pushed by `scripts/push-alert-rules.sh <org>` (the Apply workflow runs it after
`terraform apply`) to the ruler of a Cockpit metrics data source, under the
namespace named after the file. Alerts reach the group's alert manager, which
e-mails `alert_emails` (MAIR-623).

- `group/*.yml`: once per group, to `<org>-probes` (MAIR-621);
- `instance/*.yml`: once per instance, to `<org>-<env>-metrics`; `__ENV__` is
  replaced by the env name (MAIR-622).

`tests/test_alert_rules.py` checks the files (and runs `promtool` when it is
installed).
