# Platform fork: sign-in through Trino or Keycloak

Two sign-in modes, chosen at build time (`AUTH_MODE`):

- **`trino` (default, prototype):** the connector follows Trino's own external-authentication flow, as the
  Trino CLI and JDBC driver do. Trino answers an unauthenticated request with `401` and
  `WWW-Authenticate: Bearer x_redirect_server="...", x_token_server="..."`; the user signs in at the redirect
  URL (Trino sends them to the right Keycloak realm, so realms can be dynamic); the connector polls the token
  server and then sends `Authorization: Bearer <token>`. No separate Keycloak client and no realm setting.
  Tested end to end in Power BI Desktop (2026-10-22).
- **`keycloak` (fallback):** one fixed realm, Authorization Code with PKCE, public client, no secret.
  Everything below about the Keycloak client and `KEYCLOAK_*` applies to this mode only.

# Keycloak mode (fallback)

This fork signs users in with one public Keycloak client for the whole platform
(Authorization Code with PKCE, no client secret) and passes each user's own token to Trino.

## Keycloak client (once)

- Client id `powerbi-trino`, **public** (client authentication off), standard flow on, PKCE `S256`.
- Valid redirect URI: `https://oauth.powerbi.com/views/oauthredirect.html`.
- The access token must be accepted by Trino: audience mapper for Trino's audience, and the claim
  Trino uses as principal (`http-server.authentication.oauth2.principal-field`) must be present.

## Build

```
python3 build/build.py                                   # trino mode (default)
AUTH_MODE=keycloak KEYCLOAK_BASE_URL=https://<keycloak-host> KEYCLOAK_REALM=<realm> python3 build/build.py
```

Writes `dist/Trino.mez` (needs Python 3.10+, nothing else). Optional: `OAUTH_CLIENT_ID`
(default `powerbi-trino`), `OAUTH_SCOPES` (default `openid`). Nothing is committed: CI injects the values.

## Install

Copy `Trino.mez` to `Documents\Power BI Desktop\Custom Connectors`. The `.mez` is unsigned, so in Power BI
Options -> Security set "Data Extensions" to allow uncertified extensions, then restart.

## Differences from upstream

- `Trino.pq`: PKCE and `Refresh` replace the Cognito client-secret flow; `X-Trino-User` is not sent with
  OAuth (Trino takes the identity from the token, and the header would trigger an impersonation check).
- `build/build.py` builds the `.mez` without the Power Query SDK. Its `trino`-mode build works in Power BI Desktop.
