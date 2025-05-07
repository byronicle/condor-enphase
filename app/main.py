"""Main ingestion script for Condor‑Enphase.

Loads configuration via *Pydantic Settings* (env vars + optional `.env`),
pulls solar telemetry from Enphase, and writes it to InfluxDB.  Designed to run
both locally (with a checked‑in `.env`) and inside Docker/Cloud Run (with real
environment variables or Docker secrets).
"""

from __future__ import annotations

# ----------------- Standard library imports ------------------------------
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# ----------------- Third‑party imports -----------------------------------
from pydantic import Field, PositiveInt
from pydantic_settings import BaseSettings, SettingsConfigDict
from influxdb_client import Point, WritePrecision

# ----------------- First‑party imports -----------------------------------
from enphase_client import EnphaseClient
from influx_writer import InfluxWriter

# -------------------------------------------------------------------------
# Configuration model
# -------------------------------------------------------------------------

PROJECT_DIR = Path(__file__).resolve().parent


def _load_write_token() -> str:
    """Return INFLUXDB_TOKEN from env or `secrets/influxdb_token.txt`."""

    if (token := os.getenv("INFLUXDB_TOKEN")):
        return token

    secret_path = PROJECT_DIR / "secrets" / "influxdb_token.txt"
    if secret_path.exists():
        return secret_path.read_text().strip()

    raise ValueError(
        "INFLUXDB_TOKEN is required via env var or secrets/influxdb_token.txt"
    )


class Settings(BaseSettings):
    """Strongly‑typed application settings."""

    # Enphase Cloud
    enphase_client_id: Optional[str] = Field(None, env="ENPHASE_CLIENT_ID")
    enphase_client_secret: Optional[str] = Field(None, env="ENPHASE_CLIENT_SECRET")
    enphase_redirect_uri: Optional[str] = Field(None, env="ENPHASE_REDIRECT_URI")
    enphase_api_key: Optional[str] = Field(None, env="ENPHASE_API_KEY")

    # InfluxDB
    influxdb_url: str = Field("http://localhost:8086", env="INFLUXDB_URL")
    influxdb_token: str = Field(default_factory=_load_write_token)
    influxdb_org: str = Field("enphase", env="INFLUXDB_ORG")
    influxdb_bucket: str = Field("solar", env="INFLUXDB_BUCKET")

    # Behaviour
    poll_interval_seconds: PositiveInt = Field(60, env="POLL_INTERVAL_SECONDS")

    # Pydantic config – load optional `.env`, ignore unknown keys, case‑insensitive
    model_config = SettingsConfigDict(
        env_file=str(PROJECT_DIR / ".env"),
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )


SETTINGS = Settings()


# -------------------------------------------------------------------------
# Helper functions
# -------------------------------------------------------------------------

def _log_config() -> None:
    """Pretty‑print loaded configuration (excluding secrets)."""

    print("Loaded configuration (secrets hidden):")
    for key, value in SETTINGS.model_dump(exclude={"influxdb_token"}).items():
        print(f"  {key} = {value}")


# -------------------------------------------------------------------------
# Main ingestion loop
# -------------------------------------------------------------------------

def ingest_loop() -> None:  # noqa: C901  (function is long but clear)
    """Continuously pull Enphase telemetry and write it to InfluxDB."""

    _log_config()

    enphase = EnphaseClient(
        client_id=SETTINGS.enphase_client_id,
        client_secret=SETTINGS.enphase_client_secret,
        redirect_uri=SETTINGS.enphase_redirect_uri,
        api_key=SETTINGS.enphase_api_key,
    )

    influx = InfluxWriter(
        url=SETTINGS.influxdb_url,
        token=SETTINGS.influxdb_token,
        org=SETTINGS.influxdb_org,
        bucket=SETTINGS.influxdb_bucket,
    )

    try:
        systems = enphase.get_systems().get("systems", [])
        while True:
            for system in systems:
                system_id = system["system_id"]
                telemetry = enphase.get_latest_telemetry(system_id)

                # --------------- AC meters ---------------------------------
                for meter in telemetry.get("devices", {}).get("meters", []):
                    phase = meter.get("channel")
                    power = meter.get("power")
                    ts = meter.get("last_report_at")
                    if power is None or ts is None:
                        continue

                    measurement = meter.get("name") or ""
                    if measurement == "storage":
                        measurement = "storage_meter"

                    point = (
                        Point(measurement)
                        .tag("system_id", str(system_id))
                        .tag("phase", str(phase))
                        .field("power", power)
                        .time(datetime.fromtimestamp(ts, tz=timezone.utc), WritePrecision.S)
                    )
                    influx.write_api.write(bucket=SETTINGS.influxdb_bucket, record=point)

                # --------------- DC battery modules ------------------------
                for module in telemetry.get("devices", {}).get("encharges", []):
                    module_id = module.get("id")
                    power = module.get("power")
                    mode = module.get("operational_mode")
                    ts = module.get("last_report_at")
                    if power is None or ts is None:
                        continue

                    point = (
                        Point("battery_dc")
                        .tag("system_id", str(system_id))
                        .tag("module_id", str(module_id))
                        .field("power", power)
                        .field("mode", mode)
                        .time(datetime.fromtimestamp(ts, tz=timezone.utc), WritePrecision.S)
                    )
                    influx.write_api.write(bucket=SETTINGS.influxdb_bucket, record=point)

                # --------------- Daily summary -----------------------------
                summary = enphase.get_production_summary(system_id=system_id)
                ts = summary.get("last_interval_end_at")

                point = (
                    Point("daily_summary")
                    .tag("system_id", summary.get("system_id"))
                    .tag("source", summary.get("source"))
                    .tag("status", summary.get("status"))
                    .field("current_power", summary.get("current_power"))
                    .field("energy_lifetime", summary.get("energy_lifetime"))
                    .field("energy_today", summary.get("energy_today"))
                    .field("battery_charge_w", summary.get("battery_charge_w"))
                    .field("battery_discharge_w", summary.get("battery_discharge_w"))
                    .field("battery_capacity_wh", summary.get("battery_capacity_wh"))
                    .time(datetime.fromtimestamp(ts, tz=timezone.utc), WritePrecision.S)
                )
                influx.write_api.write(bucket=SETTINGS.influxdb_bucket, record=point)

            time.sleep(SETTINGS.poll_interval_seconds)

    finally:
        influx.close()
        enphase.close()


if __name__ == "__main__":
    ingest_loop()
