import os
import time
import base64
import json
from pathlib import Path

import httpx
from typing import Any, Dict, Optional, Union, List
from dotenv import load_dotenv

# Load .env variables
load_dotenv()


class EnphaseClient:
    """
    Unified Enphase client handling OAuth2 authentication and API requests.

    Example:
        client = EnphaseClient(
            client_id="your_id",
            client_secret="your_secret",
            redirect_uri="https://your.redirect",
            api_key="your_api_key",
        )
        # First, authenticate via OAuth code flow
        auth_url = client.get_authorize_url()
        # ... user visits auth_url, obtains code ...
        client.fetch_token(auth_code)
        # Then, make API calls
        systems = client.get_systems(limit=5)
    """
    TOKEN_URL = "https://api.enphaseenergy.com/oauth/token"
    AUTHORIZE_URL = "https://api.enphaseenergy.com/oauth/authorize"
    BASE_URL = "https://api.enphaseenergy.com/api/v4"
    DEFAULT_TOKEN_PATH = Path(os.getenv("ENPHASE_TOKEN_PATH", "./enphase_token.json"))

    def __init__(
        self,
        client_id: Optional[str] = None,
        client_secret: Optional[str] = None,
        redirect_uri: Optional[str] = None,
        api_key: Optional[str] = None,
        token_path: Optional[Path] = None,
        timeout: float = 10.0,
    ):
        # OAuth2 credentials
        self.client_id = client_id or os.getenv("ENPHASE_CLIENT_ID")
        self.client_secret = client_secret or os.getenv("ENPHASE_CLIENT_SECRET")
        self.redirect_uri = redirect_uri or os.getenv("ENPHASE_REDIRECT_URI")
        # API key passed as ?key= parameter
        self.api_key = api_key or os.getenv("ENPHASE_API_KEY")
        # Token storage
        self.token_path = token_path or self.DEFAULT_TOKEN_PATH
        self.token_data: Optional[Dict[str, Any]] = None
        self.token_obtained_at: Optional[float] = None

        # HTTP session for API calls
        self.session = httpx.Client(
            base_url=self.BASE_URL,
            headers={"Accept": "application/json"},
            timeout=timeout,
        )

        # Load token if exists
        self._load_token()

    def get_authorize_url(self) -> str:
        """
        Construct the OAuth2 authorization URL for user consent.
        """
        params = {
            "response_type": "code",
            "client_id": self.client_id,
            "redirect_uri": self.redirect_uri,
        }
        return f"{self.AUTHORIZE_URL}?" + httpx.QueryParams(params).to_str()

    def fetch_token(self, auth_code: str) -> None:
        """
        Exchange authorization code for tokens and save them.
        """
        headers = self._basic_auth_header()
        data = {
            "grant_type": "authorization_code",
            "code": auth_code,
            "redirect_uri": self.redirect_uri,
        }
        resp = httpx.post(self.TOKEN_URL, headers=headers, data=data)
        resp.raise_for_status()
        self.token_data = resp.json()
        self.token_obtained_at = time.time()
        self._save_token()

    def _basic_auth_header(self) -> Dict[str, str]:
        creds = f"{self.client_id}:{self.client_secret}"
        b64_creds = base64.b64encode(creds.encode()).decode()
        return {"Authorization": f"Basic {b64_creds}", "Content-Type": "application/x-www-form-urlencoded"}

    def _refresh_token(self) -> None:
        """
        Refresh the OAuth2 access token using stored refresh_token.
        """
        if not self.token_data or "refresh_token" not in self.token_data:
            raise ValueError("No refresh token available. Call fetch_token first.")
        headers = self._basic_auth_header()
        data = {"grant_type": "refresh_token", "refresh_token": self.token_data["refresh_token"]}
        resp = httpx.post(self.TOKEN_URL, headers=headers, data=data)
        resp.raise_for_status()
        self.token_data = resp.json()
        self.token_obtained_at = time.time()
        self._save_token()

    def _is_token_expired(self, buffer: int = 60) -> bool:
        if not self.token_data or not self.token_obtained_at:
            return True
        expires_in = self.token_data.get("expires_in", 0)
        return (time.time() - self.token_obtained_at) >= (expires_in - buffer)

    def _ensure_token(self) -> str:
        """
        Return a valid access token, refreshing if necessary.
        """
        if not self.token_data:
            raise ValueError("No token data; call fetch_token first.")
        if self._is_token_expired():
            self._refresh_token()
        return self.token_data["access_token"]  # type: ignore

    def _save_token(self) -> None:
        payload = {"token_data": self.token_data, "token_obtained_at": self.token_obtained_at}
        with open(self.token_path, "w") as f:
            json.dump(payload, f)

    def _load_token(self) -> None:
        if not self.token_path.exists():
            return
        try:
            with open(self.token_path, "r") as f:
                payload = json.load(f)
                self.token_data = payload.get("token_data")
                self.token_obtained_at = payload.get("token_obtained_at")
        except Exception:
            pass

    def _get(
        self, endpoint: str, params: Optional[Dict[str, Any]] = None
    ) -> Union[Dict[str, Any], List[Any]]:
        # ensure access token is fresh
        token = self._ensure_token()
        # prepare params
        params = params or {}
        if self.api_key:
            params["key"] = self.api_key
        # set auth header per request
        headers = {"Authorization": f"Bearer {token}"}
        resp = self.session.get(endpoint, params=params, headers=headers)
        resp.raise_for_status()
        return resp.json()

    def get_systems(self, limit: Optional[int] = None, offset: Optional[int] = None) -> Dict[str, Any]:
        params = {}
        if limit is not None:
            params["limit"] = limit
        if offset is not None:
            params["offset"] = offset
        return self._get("/systems", params=params)

    def get_system_details(self, system_id: int) -> Dict[str, Any]:
        return self._get(f"/systems/{system_id}")

    def get_meter_readings(self, system_id: int, start_time: Optional[int] = None, end_time: Optional[int] = None) -> Dict[str, Any]:
        params = {}
        if start_time is not None:
            params["start_at"] = start_time
        if end_time is not None:
            params["end_at"] = end_time
        return self._get(f"/systems/{system_id}/production_meter_readings", params=params)

    def get_production_summary(self, system_id: int, period: str = "day", date: Optional[str] = None) -> Dict[str, Any]:
        params = {"period": period}
        if date:
            params["date"] = date
        return self._get(f"/systems/{system_id}/summary", params=params)
    
    def get_latest_telemetry(self, system_id: int) -> Dict[str, Any]:
        params = {}
        return self._get(f"systems/{system_id}/latest_telemetry", params=params)

    def close(self) -> None:
        """
        Close the HTTP session.
        """
        self.session.close()


# Example usage:
if __name__ == "__main__":
    # Initialize with credentials and API key
    client = EnphaseClient(
        client_id=os.getenv("ENPHASE_CLIENT_ID"),
        client_secret=os.getenv("ENPHASE_CLIENT_SECRET"),
        redirect_uri=os.getenv("ENPHASE_REDIRECT_URI"),
        api_key=os.getenv("ENPHASE_API_KEY"),
    )

    # Step 1: direct user to authorize
    print("Visit:", client.get_authorize_url())
    code = input("Enter the authorization code: ")
    client.fetch_token(code)

    # Step 2: make API call
    systems = client.get_systems(limit=3)
    print(systems)

    client.close()
