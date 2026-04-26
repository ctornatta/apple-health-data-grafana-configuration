# Apple Health Grafana Configuration

> **Note:** The code and documentation in this repo were created with the assistance of [Claude](https://claude.ai) (Anthropic AI).

Grafana dashboards for Apple Health data, managed as IaC and applied via the Grafana HTTP API.

## Infrastructure

All services run as Proxmox LXC containers.

| Service | URL |
|---|---|
| Apple Health Ingester | http://\<ingester-host\>:\<port\> |
| InfluxDB v2 (v2.8.0) | http://\<influxdb-host\>:\<port\> |
| Grafana (v13.0.1) | http://\<grafana-host\>:\<port\> |

Credentials and tokens live in `.env` (gitignored).

## Data Flow

Apple Health → Health Auto Export iOS app → apple-health-ingester → InfluxDB v2 → Grafana

- [Health Auto Export](https://apps.apple.com/us/app/health-auto-export-json-csv/id1115567069) — iOS app used to export Apple Health data and send it to the ingester endpoint
- [apple-health-ingester](https://github.com/irvinlim/apple-health-ingester) — receives data from Health Auto Export and writes it to InfluxDB v2

## InfluxDB Schema

**Org:** `health-data`

**Buckets:**
- `apple_health_metrics` — all health metrics
- `apple_health_workouts` — workout data (currently empty)

**Field patterns in `apple_health_metrics`:**

| Pattern | Measurements | Fields |
|---|---|---|
| Single value | All except heart rate | `qty` (numeric), `source` (device name) |
| Min/Avg/Max | `heart_rate_count/min` only | `Avg`, `Max`, `Min`, `source` |
| Staged | `sleep_phases` only | `qty` (hours) + `value` tag = stage name (core, deep, rem, awake, asleep, inBed) |

**Full measurement list (apple_health_metrics):**
`active_energy_kcal`, `apple_exercise_time_min`, `apple_sleeping_wrist_temperature_degF`,
`apple_stand_hour_count`, `apple_stand_time_min`, `basal_energy_burned_kcal`,
`blood_glucose_mg/dL`, `blood_oxygen_saturation_%`, `cardio_recovery_count/min`,
`environmental_audio_exposure_dBASPL`, `flights_climbed_count`, `handwashing_s`,
`headphone_audio_exposure_dBASPL`, `heart_rate_count/min`, `heart_rate_variability_ms`,
`physical_effort_kcal/hr·kg`, `respiratory_rate_count/min`, `resting_heart_rate_count/min`,
`six_minute_walking_test_distance_m`, `sleep_phases`, `stair_speed_down_ft/s`,
`stair_speed_up_ft/s`, `step_count_count`, `time_in_daylight_min`, `vo2_max_ml/(kg·min)`,
`walking_asymmetry_percentage_%`, `walking_double_support_percentage_%`,
`walking_heart_rate_average_count/min`, `walking_running_distance_mi`,
`walking_speed_mi/hr`, `walking_step_length_in`, `weight_body_mass_lb`

## Applying Changes

```bash
./scripts/apply.sh
```

This script:
1. Sources `.env`
2. Creates or updates the InfluxDB datasource in Grafana (UID: `apple-health-influxdb`)
3. Pushes every `grafana/dashboards/*.json` to the Grafana API with `overwrite: true`

Dependencies: `curl`, `jq`, `envsubst`

## Repo Structure

```
grafana/
├── datasources/
│   └── influxdb.json       # Datasource template; ${VAR} placeholders substituted by apply.sh
└── dashboards/
    ├── activity.json        # Steps, energy, exercise, stand, flights, distance, daylight
    ├── glucose.json         # CGM trace, time in range (70-140 goal), GMI, daily breakdown
    ├── heart-health.json    # Heart rate, resting HR, HRV, cardio recovery, VO2 max, blood O2
    └── sleep.json           # Sleep stages stacked bar, total sleep, wrist temperature
scripts/
└── apply.sh                 # Apply everything to Grafana via HTTP API
.env                         # Gitignored — real secrets
```

## Dashboards

| File | Grafana UID | URL path |
|---|---|---|
| activity.json | `apple-health-activity` | `/d/apple-health-activity` |
| glucose.json | `apple-health-glucose` | `/d/apple-health-glucose` |
| heart-health.json | `apple-health-heart` | `/d/apple-health-heart` |
| sleep.json | `apple-health-sleep` | `/d/apple-health-sleep` |

## Adding a New Dashboard

1. Create `grafana/dashboards/<name>.json` with a unique `uid` field
2. Use datasource reference `{"type": "influxdb", "uid": "apple-health-influxdb"}` in every panel target
3. Run `./scripts/apply.sh` to push it to Grafana

## Adding a New Panel to an Existing Dashboard

1. Edit the dashboard JSON — add a new panel object to the `panels` array
2. Assign a unique `id` (integer) not used by any other panel in that dashboard
3. Set `gridPos` so it does not overlap existing panels (canvas is 24 units wide)
4. Run `./scripts/apply.sh`

## Querying InfluxDB Directly

```bash
source .env
curl -s "$INFLUXDB_URL/api/v2/query?org=$INFLUXDB_ORG" \
  -H "Authorization: Token $INFLUXDB_TOKEN" \
  -H "Content-Type: application/vnd.flux" \
  -d '<flux query>'
```

Useful schema queries:
```flux
import "influxdata/influxdb/schema"
schema.measurements(bucket: "apple_health_metrics")
schema.fieldKeys(bucket: "apple_health_metrics", predicate: (r) => r._measurement == "<name>")
```

## Deferred Work

- **Workouts dashboard**: `apple_health_workouts` bucket is currently empty. Create `grafana/dashboards/workouts.json` once data starts flowing.
- **Body metrics dashboard**: `weight_body_mass_lb` — currently no data; add when available.
- **Gait & mobility dashboard**: `walking_speed_mi/hr`, `walking_step_length_in`, `walking_asymmetry_percentage_%`, `walking_double_support_percentage_%`, `stair_speed_up_ft/s`, `stair_speed_down_ft/s`, `six_minute_walking_test_distance_m`
- **Audio & environment dashboard**: `environmental_audio_exposure_dBASPL`, `headphone_audio_exposure_dBASPL`, `handwashing_s`
