#!/usr/bin/env python3
"""
set-github-secrets.py
Reads values from bootstrap/.env and sets GitHub Actions secrets via REST API.
Usage: python bootstrap/set-github-secrets.py
"""

import base64
import re
import sys
import getpass
import requests
from pathlib import Path
from nacl import encoding, public


# ── .env loader ───────────────────────────────────────────────────────────────
def load_env(env_path: Path) -> dict:
    """Safely parse bootstrap/.env — strips quotes, skips comments/blanks."""
    if not env_path.exists():
        print(f"ERROR: {env_path} not found.")
        print("Copy bootstrap/.env.example to bootstrap/.env and fill in your values.")
        sys.exit(1)

    env = {}
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip()
        # Strip surrounding quotes
        m = re.match(r'^["\'](.+)["\']$', val)
        if m:
            val = m.group(1)
        if key:
            env[key] = val
    return env


# ── GitHub API helpers ────────────────────────────────────────────────────────
def auth_headers(token: str) -> dict:
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }


def get_public_key(owner: str, repo: str, token: str) -> dict:
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/secrets/public-key"
    resp = requests.get(url, headers=auth_headers(token))
    resp.raise_for_status()
    return resp.json()


def encrypt_secret(public_key_b64: str, secret_value: str) -> str:
    pub_key = public.PublicKey(public_key_b64.encode("utf-8"), encoding.Base64Encoder())
    sealed_box = public.SealedBox(pub_key)
    encrypted = sealed_box.encrypt(secret_value.encode("utf-8"))
    return base64.b64encode(encrypted).decode("utf-8")


def set_secret(owner: str, repo: str, token: str, name: str, value: str, key_id: str, key: str):
    encrypted = encrypt_secret(key, value)
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/secrets/{name}"
    resp = requests.put(url, headers=auth_headers(token), json={"encrypted_value": encrypted, "key_id": key_id})
    if resp.status_code in (201, 204):
        print(f"  OK  {name}")
    else:
        print(f"  FAIL  {name} - {resp.status_code}: {resp.text}")


# ── Main ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    # Locate bootstrap/.env relative to this script
    env_file = Path(__file__).parent / ".env"
    env = load_env(env_file)

    # Read repo info from .env
    owner = env.get("GITHUB_ORG", "")
    repo  = env.get("GITHUB_REPO", "")

    if not owner or not repo:
        print("ERROR: GITHUB_ORG and GITHUB_REPO must be set in bootstrap/.env")
        sys.exit(1)

    # Map .env keys → GitHub secret names
    secret_map = {
        "AZURE_CLIENT_ID":       env.get("AZURE_APP_ID", ""),
        "AZURE_TENANT_ID":       env.get("AZURE_TENANT_ID", ""),
        "AZURE_SUBSCRIPTION_ID": env.get("AZURE_SUBSCRIPTION_ID", ""),
        "AZURE_CLIENT_SECRET":   env.get("AZURE_CLIENT_SECRET", ""),
        "TF_BACKEND_RG":         env.get("AZURE_RG", ""),
        "TF_BACKEND_SA":          env.get("TF_BACKEND_SA", ""),
        "TF_BACKEND_CONTAINER":  "tfstate",
    }

    # Remove empty optional secrets (e.g. AZURE_CLIENT_SECRET if not set)
    secrets = {k: v for k, v in secret_map.items() if v and "<" not in v}

    print("=" * 60)
    print(f"  Setting GitHub Secrets -> {owner}/{repo}")
    print("=" * 60)
    print(f"  Loaded from: {env_file}")
    print(f"  Secrets to set: {list(secrets.keys())}")
    print()
    # Read PAT from .env first, fall back to interactive prompt
    token = env.get("GITHUB_PAT", "").strip()
    if not token:
        print("Enter your GitHub Personal Access Token (PAT)")
        print("Create one at: https://github.com/settings/tokens/new")
        print("Required scope: repo (classic token)")
        print()
        token = getpass.getpass("PAT: ").strip()
    if not token:
        print("No token provided. Exiting.")
        sys.exit(1)

    print()
    print("Fetching repo public key...")
    try:
        pub_key_data = get_public_key(owner, repo, token)
    except requests.HTTPError as e:
        print(f"Failed to fetch public key: {e}")
        print("Check your PAT has 'repo' scope and the repo name is correct.")
        sys.exit(1)

    key_id = pub_key_data["key_id"]
    key    = pub_key_data["key"]
    print(f"Public key fetched (key_id: {key_id})")
    print()
    print("Setting secrets:")

    for name, value in secrets.items():
        set_secret(owner, repo, token, name, value, key_id, key)

    print()
    print("Done! Verify at:")
    print(f"https://github.com/{owner}/{repo}/settings/secrets/actions")
