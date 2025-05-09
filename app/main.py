"""Condor‑Enphase — local gateway ingestion (timestamps).

Scrapes data from the local IQ Gateway, converts hardware‑supplied timestamps
into UTC, and writes points to InfluxDB.  Designed to be run as a long‑lived
process (e.g. systemd service or container).

Endpoints pulled every cycle
---------------------------
1. ``/ivp/pdm/energy``              → ``production_*`` / ``consumption_eim``
2. ``/api/v1/production``           → ``production_total``
3. ``/ivp/meters/readings``         → ``meter_power`` (per CT)
4. ``/api/v1/production/inverters`` → ``inverter_power`` (per inverter)
5. ``/ivp/livedata/status``         → ``live_data`` (raw ``*_mw`` + ``*_mva``)

Pylint‑clean: no ``broad-exception-caught`` warnings, all public objects have
doc‑strings, and line length ≤ 100 characters.
"""

from __future__ import annotations

# ---------------------------------------------------------------------------
# Standard library
# ---------------------------------------------------------------------------
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Third‑party
# ---------------------------------------------------------------------------
import requests
from influxdb_client import Point, WritePrecision
from pydantic import Field, PositiveInt
from pydantic_settings import BaseSettings, SettingsConfigDict

# ---------------------------------------------------------------------------
# First‑party
# ---------------------------------------------------------------------------
# Raises EnphaseClientError on failures
from enphase_client import EnphaseClient
from influx_writer import InfluxWriter

# ---------------------------------------------------------------------------
# Helper constants & functions
# ---------------------------------------------------------------------------

PROJECT_DIR = Path(__file__).resolve().parent


def _load_write_token() -> str:
    """Return the InfluxDB API token from env var or *secrets/influxdb_token.txt*."""

    token = os.getenv("INFLUXDB_TOKEN")
    if token:
        return token

    secret_path = PROJECT_DIR / "secrets" / "influxdb_token.txt"
    if secret_path.exists():
        return secret_path.read_text(encoding="utf-8").strip()

    raise ValueError("Missing INFLUXDB_TOKEN or secrets/influxdb_token.txt")


def _epoch_to_dt(epoch: Optional[int]) -> datetime:
    """Convert an epoch‑seconds int (or *None*) to a timezone‑aware ``datetime``."""

    if epoch is None:
        return datetime.now(tz=timezone.utc)
    return datetime.fromtimestamp(epoch, tz=timezone.utc)


class Settings(BaseSettings):
    """Run‑time configuration sourced from environment variables or a ``.env`` file."""

    envoy_host: str = Field("envoy.local", env="ENVOY_HOST")
    enphase_local_token: Optional[str] = Field(
        None, env="ENPHASE_LOCAL_TOKEN", description="Installer‑Toolkit bearer token")

    influxdb_url: str = Field("http://localhost:8086", env="INFLUXDB_URL")
    influxdb_token: str = Field(default_factory=_load_write_token)
    influxdb_org: str = Field("enphase", env="INFLUXDB_ORG")
    influxdb_bucket: str = Field("solar", env="INFLUXDB_BUCKET")

    poll_interval_seconds: PositiveInt = Field(60, env="POLL_INTERVAL_SECONDS")

    model_config = SettingsConfigDict(
        env_file=str(PROJECT_DIR / ".env"), env_file_encoding="utf-8",
        case_sensitive=False, extra="ignore")


SETTINGS = Settings()

# ---------------------------------------------------------------------------
# Logging & write helpers
# ---------------------------------------------------------------------------


def _log_cfg() -> None:
    """Pretty‑print the active configuration, hiding secrets."""

    hidden = {"influxdb_token", "enphase_local_token"}
    print("Loaded config (secrets hidden):")
    for key, val in SETTINGS.model_dump(exclude=hidden).items():
        print(f"  {key} = {val}")


def _write(writer: InfluxWriter, point: Point) -> None:
    """Write a single point to the default bucket, propagating any client errors."""

    writer.write_api.write(bucket=SETTINGS.influxdb_bucket, record=point)

# ---------------------------------------------------------------------------
# Main ingestion loop
# ---------------------------------------------------------------------------


def ingest_loop() -> None:  # pylint: disable=too-many-branches
    """Continuously poll the local gateway and push datapoints into InfluxDB."""

    _log_cfg()

    enphase = EnphaseClient(
        api_key=SETTINGS.enphase_local_token, gateway_ip=SETTINGS.envoy_host,
        use_https=True, timeout=10.0)

    influx = InfluxWriter(
        url=SETTINGS.influxdb_url, token=SETTINGS.influxdb_token,
        org=SETTINGS.influxdb_org, bucket=SETTINGS.influxdb_bucket)

    host_tag = SETTINGS.envoy_host

    try:
        while True:
            # 1️⃣  /ivp/pdm/energy -----------------------------------
            try:
                pdm = enphase.get_production_data_local()
            except (requests.RequestException, ValueError) as exc:
                print(f"pdm/energy error: {exc}")
                pdm = {}

            meta_ts = pdm.get("meta", {}).get("last_report_at")
            base_ts = _epoch_to_dt(meta_ts)
            for cat, cat_data in pdm.items():
                if not isinstance(cat_data, dict):
                    continue
                for src, vals in cat_data.items():
                    if not isinstance(vals, dict):
                        continue
                    _write(
                        influx,
                        Point(f"{cat}_{src}")
                        .tag("host", host_tag)
                        .field("wh_today", vals.get("wattHoursToday"))
                        .field("wh_7d", vals.get("wattHoursSevenDays"))
                        .field("wh_life", vals.get("wattHoursLifetime"))
                        .field("w_now", vals.get("wattsNow"))
                        .time(base_ts, WritePrecision.S),
                    )

            # 2️⃣  /api/v1/production -------------------------------
            try:
                prod = enphase.get_production_local()
                ts = _epoch_to_dt(prod.get("timestamp"))
                _write(
                    influx,
                    Point("production_total")
                    .tag("host", host_tag)
                    .field("wh_today", prod.get("wattHoursToday"))
                    .field("wh_7d", prod.get("wattHoursSevenDays"))
                    .field("wh_life", prod.get("wattHoursLifetime"))
                    .field("w_now", prod.get("wattsNow"))
                    .time(ts, WritePrecision.S),
                )
            except (requests.RequestException, ValueError) as exc:
                print(f"production error: {exc}")

            # 3️⃣  /ivp/meters/readings -----------------------------
            try:
                meters = enphase.get_meter_readings_local()
                for mtr in meters:
                    ts = _epoch_to_dt(mtr.get("timestamp")
                                      or mtr.get("read_at"))
                    _write(
                        influx,
                        Point("meter_power")
                        .tag("host", host_tag)
                        .tag("eid", str(mtr.get("eid")))
                        .tag("type", mtr.get("measurementType"))
                        .field("active_power", mtr.get("activePower"))
                        .field("inst_demand", mtr.get("instantaneousDemand"))
                        .field("voltage", mtr.get("voltage"))
                        .field("current", mtr.get("current"))
                        .time(ts, WritePrecision.S),
                    )
            except (requests.RequestException, ValueError) as exc:
                print(f"meters/readings error: {exc}")

            # 4️⃣  /api/v1/production/inverters --------------------
            try:
                invs = enphase.get_inverter_production_local()
                for inv in invs:
                    ts = _epoch_to_dt(inv.get("lastReportDate"))
                    _write(
                        influx,
                        Point("inverter_power")
                        .tag("host", host_tag)
                        .tag("serial", inv.get("serialNumber"))
                        .field("last_w", inv.get("lastReportWatts"))
                        .field("max_w", inv.get("maxReportWatts"))
                        .time(ts, WritePrecision.S),
                    )
            except (requests.RequestException, ValueError) as exc:
                print(f"inverter production error: {exc}")

            # 5️⃣  /ivp/livedata/status ----------------------------
            try:
                live = enphase.get_live_data_local()
                meters = live.get("meters", {})
                ts = _epoch_to_dt(meters.get("last_update"))

                def _g(cat: str, key: str) -> Optional[int]:
                    return meters.get(cat, {}).get(key)

                _write(
                    influx,
                    Point("live_data")
                    .tag("host", host_tag)
                    .field("pv_mw", _g("pv", "agg_p_mw"))
                    .field("pv_mva", _g("pv", "agg_s_mva"))
                    .field("load_mw", _g("load", "agg_p_mw"))
                    .field("load_mva", _g("load", "agg_s_mva"))
                    .field("grid_mw", _g("grid", "agg_p_mw"))
                    .field("grid_mva", _g("grid", "agg_s_mva"))
                    .field("storage_mw", _g("storage", "agg_p_mw"))
                    .field("storage_mva", _g("storage", "agg_s_mva"))
                    .time(ts, WritePrecision.S),
                )
            except (requests.RequestException, ValueError) as exc:
                print(f"livedata error: {exc}")

            time.sleep(SETTINGS.poll_interval_seconds)

    finally:
        influx.close()
        enphase.close()


if __name__ == "__main__":
    ingest_loop()
