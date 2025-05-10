"""Condor‑Enphase — local gateway ingestion (timestamps).

Scrapes data from the local IQ Gateway, converts hardware‑supplied timestamps
into UTC, and writes points to InfluxDB. Designed to be run as a long‑lived
process (e.g. systemd service or container).

Endpoints pulled every cycle
---------------------------
1. `/ivp/pdm/energy`              → `production_*` / `consumption_eim`
2. `/api/v1/production`           → `production_total`
3. `/ivp/meters/readings`         → `meter_power` (per CT)
4. `/api/v1/production/inverters` → `inverter_power` (per inverter)
5. `/ivp/livedata/status`         → `live_data` (raw `*_mw` + `*_mva`)

Pylint‑clean: no `broad-exception-caught` warnings, all public objects have
doc‑strings, and line length ≤ 100 characters.
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
from enphase_client import EnphaseClient
from influx_writer import InfluxWriter

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

PROJECT_DIR = Path(__file__).resolve().parent


def _load_write_token() -> str:
    """Return the InfluxDB token from env or secrets/influxdb_token.txt."""
    if token := os.getenv("INFLUXDB_TOKEN"):
        return token
    secret = PROJECT_DIR / "secrets" / "influxdb_token.txt"
    if secret.exists():
        return secret.read_text(encoding="utf-8").strip()
    raise ValueError("Missing INFLUXDB_TOKEN or secrets/influxdb_token.txt")


def _epoch_to_dt(epoch: Optional[int]) -> datetime:
    """Convert epoch seconds to UTC datetime; fallback to now if None."""
    return (
        datetime.fromtimestamp(epoch, tz=timezone.utc)
        if epoch is not None
        else datetime.now(tz=timezone.utc)
    )


class Settings(BaseSettings):
    """Application settings from env or .env file."""

    envoy_host: str = Field("envoy.local", env="ENVOY_HOST")
    enphase_local_token: Optional[str] = Field(
        None, env="ENPHASE_LOCAL_TOKEN", description="Bearer token"
    )

    influxdb_url: str = Field("http://localhost:8086", env="INFLUXDB_URL")
    influxdb_token: str = Field(default_factory=_load_write_token)
    influxdb_org: str = Field("enphase", env="INFLUXDB_ORG")
    influxdb_bucket: str = Field("solar", env="INFLUXDB_BUCKET")

    poll_interval_seconds: PositiveInt = Field(
        60, env="POLL_INTERVAL_SECONDS"
    )

    model_config = SettingsConfigDict(
        env_file=str(PROJECT_DIR / ".env"),
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )


SETTINGS = Settings()


def _log_cfg() -> None:
    """Print loaded config, hiding sensitive values."""
    hide = {"influxdb_token", "enphase_local_token"}
    print("Config:")
    for k, v in SETTINGS.model_dump(exclude=hide).items():
        print(f"  {k} = {v}")


def _write(writer: InfluxWriter, point: Point) -> None:
    """Write one point into InfluxDB."""
    writer.write_api.write(
        bucket=SETTINGS.influxdb_bucket, record=point
    )


def ingest_loop() -> None:
    """Continuously poll IQ Gateway and push data to InfluxDB."""
    _log_cfg()

    enphase = EnphaseClient(
        api_key=SETTINGS.enphase_local_token,
        gateway_ip=SETTINGS.envoy_host,
        use_https=True,
        timeout=10.0,
    )
    influx = InfluxWriter(
        url=SETTINGS.influxdb_url,
        token=SETTINGS.influxdb_token,
        org=SETTINGS.influxdb_org,
        bucket=SETTINGS.influxdb_bucket,
    )
    host_tag = SETTINGS.envoy_host

    try:
        while True:
            # 1️⃣  Production & consumption energy -----------------
            try:
                pdm = enphase.get_production_data_local()
            except (requests.RequestException, ValueError) as exc:
                print(f"pdm/energy error: {exc}")
                pdm = {}
            meta = pdm.get("meta", {})
            base_ts = _epoch_to_dt(meta.get("last_report_at"))
            for cat, cat_data in pdm.items():
                if not isinstance(cat_data, dict):
                    continue
                for src, vals in cat_data.items():
                    if not isinstance(vals, dict):
                        continue
                    pt = (
                        Point(f"{cat}_{src}")
                        .tag("host", host_tag)
                        .field("wh_today", vals.get("wattHoursToday"))
                        .field("wh_7d", vals.get("wattHoursSevenDays"))
                        .field("wh_life", vals.get("wattHoursLifetime"))
                        .field("w_now", vals.get("wattsNow"))
                        .time(base_ts, WritePrecision.S)
                    )
                    _write(influx, pt)

            # 2️⃣  Total production meter -------------------------
            try:
                prod = enphase.get_production_local()
                ts = _epoch_to_dt(prod.get("timestamp"))
                pt = (
                    Point("production_total")
                    .tag("host", host_tag)
                    .field("wh_today", prod.get("wattHoursToday"))
                    .field("wh_7d", prod.get("wattHoursSevenDays"))
                    .field("wh_life", prod.get("wattHoursLifetime"))
                    .field("w_now", prod.get("wattsNow"))
                    .time(ts, WritePrecision.S)
                )
                _write(influx, pt)
            except (requests.RequestException, ValueError) as exc:
                print(f"production error: {exc}")

            # 3️⃣  Per-CT meter readings --------------------------
            try:
                meters = enphase.get_meter_readings_local()
            except (requests.RequestException, ValueError) as exc:
                print(f"meters/readings error: {exc}")
            else:
                for mtr in meters:
                    ts = _epoch_to_dt(
                        mtr.get("timestamp") or mtr.get("read_at")
                    )
                    pt = (
                        Point("meter_power")
                        .tag("host", host_tag)
                        .tag("eid", str(mtr.get("eid")))
                        .tag("type", mtr.get("measurementType"))
                        .field("active_power", mtr.get("activePower"))
                        .field("inst_demand", mtr.get("instantaneousDemand"))
                        .field("voltage", mtr.get("voltage"))
                        .field("current", mtr.get("current"))
                        .time(ts, WritePrecision.S)
                    )
                    _write(influx, pt)

            # 4️⃣  Per-inverter production -----------------------
            try:
                invs = enphase.get_inverter_production_local()
            except (requests.RequestException, ValueError) as exc:
                print(f"inverter production error: {exc}")
            else:
                for inv in invs:
                    ts = _epoch_to_dt(inv.get("lastReportDate"))
                    pt = (
                        Point("inverter_power")
                        .tag("host", host_tag)
                        .tag("serial", inv.get("serialNumber"))
                        .field("last_w", inv.get("lastReportWatts"))
                        .field("max_w", inv.get("maxReportWatts"))
                        .time(ts, WritePrecision.S)
                    )
                    _write(influx, pt)

            # 5️⃣  Live meter snapshot --------------------------------
            try:
                live = enphase.get_live_data_local()
            except (requests.RequestException, ValueError) as exc:
                print(f"livedata error: {exc}")
            else:
                conn = live.get("connection", {})
                state = conn.get("sc_stream", "disabled")
                if state != "enabled":
                    # try once to turn on the stream and re-fetch
                    try:
                        enphase.enable_live_stream()
                        live = enphase.get_live_data_local()
                        conn = live.get("connection", {})
                        state = conn.get("sc_stream", "disabled")
                    except (requests.RequestException, ValueError) as exc:
                        print(f"livedata enable error: {exc}")
                if state == "enabled":
                    meters = live.get("meters", {})
                    ts = _epoch_to_dt(meters.get("last_update"))

                    def _g(cat: str, key: str) -> Optional[int]:
                        return meters.get(cat, {}).get(key)
                    pt = (
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
                        .time(ts, WritePrecision.S)
                    )
                    _write(influx, pt)
                else:
                    print("Live-data stream disabled; skipping write.")

            time.sleep(SETTINGS.poll_interval_seconds)

    finally:
        influx.close()
        enphase.close()


if __name__ == "__main__":
    ingest_loop()
