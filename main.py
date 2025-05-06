import os
import time
from datetime import datetime, timezone

from enphase_client import EnphaseClient
from influx_writer import InfluxWriter
from influxdb_client import Point, WritePrecision

from dotenv import load_dotenv
from pathlib import Path

print("Working directory:", os.getcwd())

# Load variables from .env
load_dotenv(dotenv_path=Path(__file__).resolve().parent / ".env")

# Load environment variables
load_dotenv()

# Configuration (via environment variables)
ENPHASE_CLIENT_ID = os.getenv("ENPHASE_CLIENT_ID")
ENPHASE_CLIENT_SECRET = os.getenv("ENPHASE_CLIENT_SECRET")
ENPHASE_REDIRECT_URI = os.getenv("ENPHASE_REDIRECT_URI")
ENPHASE_API_KEY = os.getenv("ENPHASE_API_KEY")
# InfluxDB
INFLUX_URL = os.getenv("INFLUXDB_URL", "http://localhost:8086")
INFLUX_TOKEN = os.getenv("INFLUXDB_TOKEN")
INFLUX_ORG = os.getenv("INFLUXDB_ORG", "enphase")
INFLUX_BUCKET = os.getenv("INFLUXDB_BUCKET", "solar")
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL_SECONDS", "60"))  # seconds


def ingest_loop():
    # Initialize Enphase and Influx clients
    enphase = EnphaseClient(
        client_id=ENPHASE_CLIENT_ID,
        client_secret=ENPHASE_CLIENT_SECRET,
        redirect_uri=ENPHASE_REDIRECT_URI,
        api_key=ENPHASE_API_KEY,
    )
    influx = InfluxWriter(
        url=INFLUX_URL,
        token=INFLUX_TOKEN,
        org=INFLUX_ORG,
        bucket=INFLUX_BUCKET,
    )

    try:
        # Fetch list of systems once
        sys_list = enphase.get_systems().get("systems", [])

        while True:
            for sys in sys_list:
                system_id = sys["system_id"]
                telemetry = enphase.get_latest_telemetry(system_id)
                now = datetime.now(timezone.utc)

                # ---- Write meter-level (AC) data ----
                for meter in telemetry.get("devices", {}).get("meters", []):
                    phase = meter.get("channel")
                    power = meter.get("power")
                    ts = meter.get("last_report_at")
                    if power is None or ts is None:
                        continue
                    # measurement name: production, consumption, storage_meter
                    meas = meter.get("name")
                    if meas == "storage":
                        meas = "storage_meter"

                    point = (
                        Point(meas)
                        .tag("system_id", str(system_id))
                        .tag("phase", str(phase))
                        .field("power", power)
                        .time(datetime.fromtimestamp(ts, tz=timezone.utc), WritePrecision.S)
                    )
                    influx.write_api.write(bucket=INFLUX_BUCKET, record=point)

                # ---- Write battery module (DC) data ----
                for mod in telemetry.get("devices", {}).get("encharges", []):
                    mod_id = mod.get("id")
                    power = mod.get("power")
                    mode = mod.get("operational_mode")
                    ts = mod.get("last_report_at")
                    if power is None or ts is None:
                        continue

                    point = (
                        Point("battery_dc")
                        .tag("system_id", str(system_id))
                        .tag("module_id", str(mod_id))
                        .field("power", power)
                        .field("mode", mode)
                        .time(datetime.fromtimestamp(ts, tz=timezone.utc), WritePrecision.S)
                    )
                    influx.write_api.write(bucket=INFLUX_BUCKET, record=point)

                # ---- Write Daily Summary data ----
                summary = enphase.get_production_summary(system_id=system_id)

                ts = summary.get("last_interval_end_at")

                fields = {
                    "current_power": summary.get("current_power"),
                    "energy_lifetime": summary.get("energy_lifetime"),
                    "energy_today": summary.get("energy_today"),
                    "battery_charge_w": summary.get("battery_charge_w"),
                    "battery_discharge_w": summary.get("battery_discharge_w"),
                    "battery_capacity_wh": summary.get("battery_capacity_wh"),
                }

                # Construct and write the point in one go
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
                influx.write_api.write(bucket=INFLUX_BUCKET, record=point)

            # Sleep until next poll
            time.sleep(POLL_INTERVAL)
    finally:
        influx.close()
        enphase.close()


if __name__ == "__main__":
    ingest_loop()
