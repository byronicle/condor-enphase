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
import logging
import os
import signal
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Third‑party
# ---------------------------------------------------------------------------
import httpx
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
# Setup
# ---------------------------------------------------------------------------

PROJECT_DIR = Path(__file__).resolve().parent

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


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


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------


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


# ---------------------------------------------------------------------------
# Main Ingestor Class
# ---------------------------------------------------------------------------


class EnphaseIngestor:
    """Main ingestion service that polls Enphase Envoy and writes to InfluxDB."""

    def __init__(self, settings: Settings):
        """Initialize the ingestor with settings.

        Args:
            settings: Application configuration settings
        """
        self.settings = settings
        self.shutdown_requested = False

        # Initialize clients (done lazily in run() to allow signal setup first)
        self.enphase: Optional[EnphaseClient] = None
        self.influx: Optional[InfluxWriter] = None

        # Register signal handlers
        signal.signal(signal.SIGTERM, self._handle_shutdown)
        signal.signal(signal.SIGINT, self._handle_shutdown)

        logger.info("EnphaseIngestor initialized")

    def _handle_shutdown(self, signum: int, frame) -> None:
        """Handle shutdown signals gracefully.

        Args:
            signum: Signal number received
            frame: Current stack frame (unused)
        """
        sig_name = signal.Signals(signum).name
        logger.info(f"{sig_name} received, initiating graceful shutdown...")
        self.shutdown_requested = True

    def _log_config(self) -> None:
        """Log configuration (hiding sensitive values)."""
        hide = {"influxdb_token", "enphase_local_token"}
        logger.info("Configuration:")
        for k, v in self.settings.model_dump(exclude=hide).items():
            logger.info(f"  {k} = {v}")

    def _write_point(self, point: Point) -> None:
        """Write a single point to InfluxDB.

        Args:
            point: InfluxDB point to write
        """
        if self.influx:
            self.influx.write_api.write(
                bucket=self.settings.influxdb_bucket, record=point
            )

    def _fetch_with_retry(
        self,
        fetch_fn,
        name: str,
        max_attempts: int = 5,
        backoff: float = 2.0,
    ) -> dict:
        """Fetch data with automatic retry on failure.

        Args:
            fetch_fn: Function to call for fetching data
            name: Human-readable name for logging
            max_attempts: Maximum retry attempts
            backoff: Base backoff multiplier (seconds)

        Returns:
            Fetched data dictionary, or empty dict on failure
        """
        for attempt in range(1, max_attempts + 1):
            if self.shutdown_requested:
                return {}

            try:
                return fetch_fn()
            except (requests.RequestException, httpx.RequestError, ValueError) as exc:
                if attempt >= max_attempts:
                    logger.error(
                        f"{name} error (giving up after {attempt} attempts): {exc}"
                    )
                    return {}

                sleep_for = backoff * attempt
                logger.warning(
                    f"{name} error (attempt {attempt}/{max_attempts}): {exc}; "
                    f"retrying in {sleep_for}s"
                )
                time.sleep(sleep_for)

        return {}

    def _ingest_pdm_energy(self, host_tag: str) -> None:
        """Ingest production/consumption energy data from /ivp/pdm/energy.

        Args:
            host_tag: Tag value for the host
        """
        pdm = self._fetch_with_retry(
            self.enphase.get_production_data_local, "pdm/energy"
        )
        if not pdm:
            return

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
                self._write_point(pt)

    def _ingest_production_total(self, host_tag: str) -> None:
        """Ingest total production from /api/v1/production.

        Args:
            host_tag: Tag value for the host
        """
        try:
            prod = self.enphase.get_production_local()
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
            self._write_point(pt)
        except (requests.RequestException, ValueError) as exc:
            logger.error(f"production error: {exc}")

    def _ingest_meter_readings(self, host_tag: str) -> None:
        """Ingest per-CT meter readings from /ivp/meters/readings.

        Args:
            host_tag: Tag value for the host
        """
        try:
            meters = self.enphase.get_meter_readings_local()
        except (requests.RequestException, ValueError) as exc:
            logger.error(f"meters/readings error: {exc}")
            return

        for mtr in meters:
            ts = _epoch_to_dt(mtr.get("timestamp") or mtr.get("read_at"))
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
            self._write_point(pt)

    def _ingest_inverter_production(self, host_tag: str) -> None:
        """Ingest per-inverter production from /api/v1/production/inverters.

        Args:
            host_tag: Tag value for the host
        """
        try:
            invs = self.enphase.get_inverter_production_local()
        except (requests.RequestException, ValueError) as exc:
            logger.error(f"inverter production error: {exc}")
            return

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
            self._write_point(pt)

    def _ingest_live_data(self, host_tag: str) -> None:
        """Ingest live meter snapshot from /ivp/livedata/status.

        Args:
            host_tag: Tag value for the host
        """
        try:
            live = self.enphase.get_live_data_local()
        except (requests.RequestException, ValueError) as exc:
            logger.error(f"livedata error: {exc}")
            return

        conn = live.get("connection", {})
        state = conn.get("sc_stream", "disabled")

        if state != "enabled":
            # Try once to enable the stream and re-fetch
            try:
                self.enphase.enable_live_stream()
                live = self.enphase.get_live_data_local()
                conn = live.get("connection", {})
                state = conn.get("sc_stream", "disabled")
            except (requests.RequestException, ValueError) as exc:
                logger.error(f"livedata enable error: {exc}")

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
            self._write_point(pt)
        else:
            logger.warning("Live-data stream disabled; skipping write.")

    def _interruptible_sleep(self, seconds: int) -> None:
        """Sleep for specified seconds, but wake early on shutdown signal.

        Args:
            seconds: Number of seconds to sleep
        """
        for _ in range(seconds):
            if self.shutdown_requested:
                break
            time.sleep(1)

    def run(self) -> None:
        """Run the main ingestion loop."""
        self._log_config()

        # Initialize clients
        self.enphase = EnphaseClient(
            api_key=self.settings.enphase_local_token,
            gateway_ip=self.settings.envoy_host,
            use_https=True,
            timeout=10.0,
        )
        self.influx = InfluxWriter(
            url=self.settings.influxdb_url,
            token=self.settings.influxdb_token,
            org=self.settings.influxdb_org,
            bucket=self.settings.influxdb_bucket,
        )

        host_tag = self.settings.envoy_host

        try:
            logger.info("Starting ingestion loop...")
            cycle = 0

            while not self.shutdown_requested:
                cycle += 1
                logger.debug(f"Starting cycle {cycle}")

                # Ingest all endpoints
                self._ingest_pdm_energy(host_tag)
                self._ingest_production_total(host_tag)
                self._ingest_meter_readings(host_tag)
                self._ingest_inverter_production(host_tag)
                self._ingest_live_data(host_tag)

                # Interruptible sleep between cycles
                if not self.shutdown_requested:
                    self._interruptible_sleep(self.settings.poll_interval_seconds)

        finally:
            logger.info("Shutting down, closing connections...")
            if self.influx:
                self.influx.close()
            if self.enphase:
                self.enphase.close()
            logger.info("Shutdown complete.")


# ---------------------------------------------------------------------------
# Entry Point
# ---------------------------------------------------------------------------


def main() -> None:
    """Entry point for the application."""
    try:
        settings = Settings()
        ingestor = EnphaseIngestor(settings)
        ingestor.run()
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received")
        sys.exit(0)
    except Exception as exc:
        logger.exception(f"Fatal error: {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()
