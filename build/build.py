#!/usr/bin/env python3
"""Build Trino.mez with the platform's Keycloak OAuth settings baked in.

A .mez is a zip of the connector files, so this needs no Power Query SDK or .NET.
Settings come from the environment, so CI injects them and nothing is committed:

  AUTH_MODE           trino (default): use Trino's own external-authentication flow, the realm
                      comes from Trino; nothing else is needed.
                      keycloak: PKCE against one fixed realm, needs the settings below.
  KEYCLOAK_BASE_URL   e.g. https://keycloak.example.com   (keycloak mode)
  KEYCLOAK_REALM      e.g. dataplatform                    (keycloak mode)
  OAUTH_CLIENT_ID     default: powerbi-trino   (a public client, no secret)
  OAUTH_SCOPES        default: openid

Usage: python3 build/build.py [output.mez]   (default: dist/Trino.mez)
"""
import os
import sys
import zipfile
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Trino"
SOURCE_FILES = ["Trino.pq", "Diagnostics.pqm", "resources.resx"] + [
    f"Trino{size}.png" for size in (16, 20, 24, 32, 40, 48, 64, 80)
]
FIXED_TIME = (2026, 1, 1, 0, 0, 0)  # same input, same bytes


def setting(name: str, default: str | None = None) -> str:
    value = os.environ.get(name, default)
    if not value:
        sys.exit(f"error: set {name}")
    return value.strip()


def main() -> None:
    mode = setting("AUTH_MODE", "trino")
    if mode not in ("trino", "keycloak"):
        sys.exit("error: AUTH_MODE must be trino or keycloak")
    oauth_files = {"oauth_config_mode.txt": mode}
    if mode == "keycloak":
        base = setting("KEYCLOAK_BASE_URL").rstrip("/")
        realm = setting("KEYCLOAK_REALM")
        parsed = urlparse(base)
        if parsed.scheme != "https" or not parsed.netloc:
            sys.exit("error: KEYCLOAK_BASE_URL must be an https URL")
        oidc = f"{base}/realms/{realm}/protocol/openid-connect"
        oauth_files.update({
            "oauth_config_client_id.txt": setting("OAUTH_CLIENT_ID", "powerbi-trino"),
            "oauth_config_authorize_uri.txt": f"{oidc}/auth",
            "oauth_config_token_uri.txt": f"{oidc}/token",
            "oauth_config_scopes.txt": setting("OAUTH_SCOPES", "openid"),
        })

    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "dist" / "Trino.mez"
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as mez:
        for name in SOURCE_FILES:
            mez.writestr(zipfile.ZipInfo(name, FIXED_TIME), (SRC / name).read_bytes(), zipfile.ZIP_DEFLATED)
        for name, value in oauth_files.items():
            mez.writestr(zipfile.ZipInfo(name, FIXED_TIME), value.encode("utf-8"), zipfile.ZIP_DEFLATED)
    print(f"wrote {out} ({out.stat().st_size} bytes), auth mode {mode}")


if __name__ == "__main__":
    main()
