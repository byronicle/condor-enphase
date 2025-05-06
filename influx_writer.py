from influxdb_client import InfluxDBClient, Point, WritePrecision
from influxdb_client.client.write_api import SYNCHRONOUS
from datetime import datetime, timezone
from typing import Dict


class InfluxWriter:
    """
    Handles writing Enphase data to InfluxDB.
    """

    def __init__(self, url: str, token: str, org: str, bucket: str):
        self.bucket = bucket
        self.client = InfluxDBClient(url=url, token=token, org=org)
        self.write_api = self.client.write_api(write_options=SYNCHRONOUS)

    def write_meter_reading(self, system_id: int, reading: Dict[str, int]) -> None:
        """
        Write a single meter reading to InfluxDB.

        Args:
            system_id: ID of the solar system.
            reading: A dictionary with 'value' and 'read_at' keys.
        """
        timestamp = datetime.fromtimestamp(reading["read_at"], tz=timezone.utc)
        point = (
            Point("meter_reading")
            .tag("system_id", str(system_id))
            .field("value", reading["value"])
            .time(timestamp, WritePrecision.S)
        )
        self.write_api.write(bucket=self.bucket, record=point)

    def close(self) -> None:
        """
        Close the InfluxDB client.
        """
        self.client.close()


# Optional: usage example
if __name__ == "__main__":
    import os

    influx = InfluxWriter(
        url=os.getenv("INFLUXDB_URL"),
        token=os.getenv("INFLUXDB_TOKEN"),
        org=os.getenv("INFLUXDB_ORG"),
        bucket=os.getenv("INFLUXDB_BUCKET")
    )

    sample = {"value": 12345678, "read_at": 1745260500}
    influx.write_meter_reading(system_id=4961570, reading=sample)
    influx.close()
