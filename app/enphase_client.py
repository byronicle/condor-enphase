"""Enphase client for Cloud API v4 and local IQ Gateway API.

Handles OAuth2 token management for the cloud API and bearer‑token auth for the
local gateway.  Provides convenience wrappers around commonly‑used endpoints.

Only the core ergonomic / lint fixes are touched here (encoding, broad‑except,
long lines, missing docstrings). Behaviour is unchanged.
"""

from __future__ import annotations

import base64
import json
import os
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Union

import httpx
from dotenv import load_dotenv

# Load .env for local dev (has no effect in production containers)
load_dotenv()


class EnphaseClient:  # pylint: disable=too-many-instance-attributes
    """High‑level wrapper for both Enphase cloud and local APIs."""

    # OAuth2 / Cloud endpoints
    TOKEN_URL = "https://api.enphaseenergy.com/oauth/token"
    AUTHORIZE_URL = "https://api.enphaseenergy.com/oauth/authorize"
    CLOUD_BASE_URL = "https://api.enphaseenergy.com/api/v4"
    DEFAULT_TOKEN_PATH = Path(
        os.getenv("ENPHASE_TOKEN_PATH", "./enphase_token.json"))

    # ---------------------------------------------------------------------
    # Construction
    # ---------------------------------------------------------------------

    def __init__(
        self,
        client_id: Optional[str] = None,
        client_secret: Optional[str] = None,
        redirect_uri: Optional[str] = None,
        api_key: Optional[str] = None,
        gateway_ip: Optional[str] = None,
        use_https: bool = True,
        timeout: float = 10.0,
    ) -> None:
        """Create a cloud or local client depending on *gateway_ip*.

        Args:
            client_id: OAuth2 client‑id (cloud).
            client_secret: OAuth2 secret (cloud).
            redirect_uri: OAuth2 redirect‑uri (cloud).
            api_key: Cloud API key **or** local bearer token.
            gateway_ip: If supplied, talk to the local gateway instead of cloud.
            use_https: Use HTTPS when talking to local gateway.
            timeout: HTTP timeout in seconds.
        """

        self.api_key = api_key or os.getenv("ENPHASE_API_KEY")
        self.timeout = timeout
        self.local_mode: bool
        self._local_token: Optional[str]

        if gateway_ip:  # ------------------------- Local mode ------------
            scheme = "https" if use_https else "http"
            self.base_url = f"{scheme}://{gateway_ip}"
            self.local_mode = True
            self._local_token = self.api_key
            self.session = httpx.Client(
                base_url=self.base_url,
                headers={"Accept": "application/json"},
                timeout=self.timeout,
                verify=False,  # self‑signed cert on the gateway
            )
        else:  # --------------------------- Cloud / OAuth2 mode ---------
            self.client_id = client_id or os.getenv("ENPHASE_CLIENT_ID")
            self.client_secret = client_secret or os.getenv(
                "ENPHASE_CLIENT_SECRET")
            self.redirect_uri = redirect_uri or os.getenv(
                "ENPHASE_REDIRECT_URI")
            self.token_path = self.DEFAULT_TOKEN_PATH
            self.token_data: Optional[Dict[str, Any]] = None
            self.token_obtained_at: Optional[float] = None

            self.base_url = self.CLOUD_BASE_URL
            self.local_mode = False
            self.session = httpx.Client(
                base_url=self.base_url,
                headers={"Accept": "application/json"},
                timeout=self.timeout,
            )
            self._load_token()

    # ------------------------------------------------------------------
    # Cloud OAuth helpers
    # ------------------------------------------------------------------

    def get_authorize_url(self) -> str:
        """Return the user‑consent URL for OAuth2."""
        params = {
            "response_type": "code",
            "client_id": self.client_id,
            "redirect_uri": self.redirect_uri,
        }
        return f"{self.AUTHORIZE_URL}?{httpx.QueryParams(params)}"

    def fetch_token(self, auth_code: str) -> None:
        """Exchange auth *code* for access & refresh tokens and save them."""
        headers = self._basic_auth_header()
        data = {
            "grant_type": "authorization_code",
            "code": auth_code,
            "redirect_uri": self.redirect_uri,
        }
        resp = httpx.post(self.TOKEN_URL, headers=headers,
                          data=data, timeout=self.timeout)
        resp.raise_for_status()
        self.token_data = resp.json()
        self.token_obtained_at = time.time()
        self._save_token()

    # ----------------------- Internal helpers ---------------------------

    def _basic_auth_header(self) -> Dict[str, str]:
        creds = f"{self.client_id}:{self.client_secret}"
        b64_creds = base64.b64encode(creds.encode()).decode()
        return {
            "Authorization": f"Basic {b64_creds}",
            "Content-Type": "application/x-www-form-urlencoded",
        }

    def _refresh_token(self) -> None:
        """Refresh OAuth access token using the stored refresh token."""
        if not self.token_data or "refresh_token" not in self.token_data:
            raise ValueError(
                "No refresh token available. Call fetch_token first.")
        headers = self._basic_auth_header()
        data = {
            "grant_type": "refresh_token",
            "refresh_token": self.token_data["refresh_token"],
        }
        resp = httpx.post(self.TOKEN_URL, headers=headers,
                          data=data, timeout=self.timeout)
        resp.raise_for_status()
        self.token_data = resp.json()
        self.token_obtained_at = time.time()
        self._save_token()

    def _is_token_expired(self, buffer: int = 60) -> bool:
        """Return *True* if the OAuth access token is (almost) expired."""
        if not self.token_data or not self.token_obtained_at:
            return True
        return (time.time() - self.token_obtained_at) >= (
            self.token_data.get("expires_in", 0) - buffer
        )

    def _ensure_token(self) -> str:
        """Return a valid bearer token for subsequent API calls."""
        if self.local_mode:
            if not self._local_token:
                raise ValueError(
                    "Local token (api_key) is required in local mode.")
            return self._local_token

        if not self.token_data:
            raise ValueError("No token data; call fetch_token first.")
        if self._is_token_expired():
            self._refresh_token()
        return str(self.token_data["access_token"])

    def _save_token(self) -> None:
        """Persist token JSON to *token_path* (UTF‑8)."""
        payload = {
            "token_data": self.token_data,
            "token_obtained_at": self.token_obtained_at,
        }
        with open(self.token_path, "w", encoding="utf-8") as fp:
            json.dump(payload, fp)

    def _load_token(self) -> None:
        """Load token JSON from *token_path* if it exists."""
        if not self.token_path.exists():
            return
        try:
            payload = json.loads(self.token_path.read_text(encoding="utf-8"))
            self.token_data = payload.get("token_data")
            self.token_obtained_at = payload.get("token_obtained_at")
        except (json.JSONDecodeError, OSError):
            # Corrupt file – ignore and start fresh
            self.token_data = None
            self.token_obtained_at = None

    # ------------------------------------------------------------------
    # Low‑level HTTP helper
    # ------------------------------------------------------------------

    def _get(
            self,
            endpoint: str,
            params: Optional[Dict[str, Any]] = None
    ) -> Union[Dict[str, Any], List[Any]]:
        """GET *endpoint* (relative path) and return JSON payload."""
        token = self._ensure_token()
        headers = {"Authorization": f"Bearer {token}"}
        params = params or {}
        if not self.local_mode and self.api_key:
            params["key"] = self.api_key
        resp = self.session.get(endpoint, params=params,
                                headers=headers, timeout=self.timeout)
        resp.raise_for_status()
        return resp.json()

    # ------------------------------------------------------------------
    # Cloud API wrappers
    # ------------------------------------------------------------------

    def get_systems(
            self,
            limit: Optional[int] = None, offset: Optional[int] = None
    ) -> Dict[str, Any]:
        """List systems accessible to this account."""
        params: Dict[str, Any] = {}
        if limit is not None:
            params["limit"] = limit
        if offset is not None:
            params["offset"] = offset
        return self._get("/systems", params=params)

    def get_system_details(self, system_id: int) -> Dict[str, Any]:
        """Detailed info about one system."""
        return self._get(f"/systems/{system_id}")

    def get_meter_readings(
        self,
        system_id: int,
        start_time: Optional[int] = None,
        end_time: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Granular meter readings for a time window."""
        params: Dict[str, Any] = {}
        if start_time is not None:
            params["start_at"] = start_time
        if end_time is not None:
            params["end_at"] = end_time
        endpoint = f"/systems/{system_id}/production_meter_readings"
        return self._get(endpoint, params=params)

    def get_production_summary(
        self,
        system_id: int,
        period: str = "day",
        date: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Aggregated production/consumption summary."""
        params = {"period": period}
        if date:
            params["date"] = date
        return self._get(f"/systems/{system_id}/summary", params=params)

    def get_latest_telemetry(self, system_id: int) -> Dict[str, Any]:
        """Most recent telemetry snapshot."""
        return self._get(f"/systems/{system_id}/latest_telemetry")

    # ------------------------------------------------------------------
    # Local Gateway API wrappers
    # ------------------------------------------------------------------

    def get_meter_details_local(self) -> List[Dict[str, Any]]:
        """Return static metadata for site meters."""
        return self._get("/ivp/meters")

    def get_meter_readings_local(self) -> List[Dict[str, Any]]:
        """Current power readings (AC) from site meters."""
        return self._get("/ivp/meters/readings")

    def get_production_local(self) -> Dict[str, Any]:
        """Legacy production endpoint (AC + DC)."""
        return self._get("/api/v1/production")

    def get_production_data_local(self) -> Dict[str, Any]:
        """Per‑interval production/consumption energy."""
        return self._get("/ivp/pdm/energy")

    def get_inverter_production_local(self) -> List[Dict[str, Any]]:
        """Per‑inverter DC power."""
        return self._get("/api/v1/production/inverters")

    def get_live_data_local(self) -> Dict[str, Any]:
        """Live data snapshot from gateway."""
        return self._get("/ivp/livedata/status")

    def get_power_consumption_local(self) -> Dict[str, Any]:
        """Detailed consumption report."""
        return self._get("/ivp/meters/reports/consumption")

    def enable_live_stream(self) -> str:
        """
        Enable the gateway’s live‑data stream.

        Returns
        -------
        str
            The resulting stream state (``"enabled"`` or ``"disabled"``).

        Raises
        ------
        RuntimeError
            If called when the client is *not* in local‑mode.
        httpx.HTTPStatusError
            If the gateway returns a non‑2xx response.
        """
        if not self.local_mode:
            raise RuntimeError(
                "enable_live_stream is valid only in local mode")

        token = self._ensure_token()
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }
        payload = {"enable": 1}

        # POST once to turn the stream on
        resp = self.session.post(
            "/ivp/livedata/stream",
            headers=headers,
            json=payload,
            timeout=self.timeout,
        )
        resp.raise_for_status()

        return resp.json()
    # ------------------------------------------------------------------
    # Cleanup
    # ------------------------------------------------------------------

    def close(self) -> None:
        """Close the underlying HTTP session."""
        self.session.close()
