#!/usr/bin/env python3
"""
set-github-secrets.py
=====================
Pushes GitHub Actions secrets to the platform repo (AI-RentalApp-Ledger)
and/or the build repo (RentalApp-Build) via the GitHub REST API.

Reads all values from bootstrap/.env — never from environment variables or
command-line arguments (secrets stay out of shell history).

Usage:
    python bootstrap/set-github-secrets.py                   # push to both repos
    python bootstrap/set-github-secrets.py --repo platform   # platform repo only
    python bootstrap/set-github-secrets.py --repo build      # build repo only
    python bootstrap/set-github-secrets.py --dry-run         # preview, no changes
    python bootstrap/set-github-secrets.py --list            # show existing secret names

Prerequisites:
    pip install requests pynacl

    bootstrap/.env  (copy from bootstrap/.env.example and fill in your values)
    GITHUB_PAT in .env — classic PAT with 'repo' scope on both repos
"""

import argparse
import base64
import re
import subprocess
import sys
import getpass
import requests
from pathlib import Path
from nacl import encoding, public


# ── Key Vault helper ──────────────────────────────────────────────────────────
def kv_get_secret(vault_name: str, secret_name: str) -> str:
    """Fetch a secret from Azure Key Vault via az CLI. Returns empty string on failure."""
    if not vault_name:
        return ""
    try:
        result = subprocess.run(
            ["az", "keyvault", "secret", "show",
             "--vault-name", vault_name,
             "--name", secret_name,
             "--query", "value", "-o", "tsv"],
            capture_output=True, text=True, timeout=15,
        )
        return result.stdout.strip() if result.returncode == 0 else ""
    except Exception:
        return ""


# ── .env loader ───────────────────────────────────────────────────────────────
def load_env(env_path: Path) -> dict:
    """Safely parse bootstrap/.env — strips quotes, skips comments and blanks."""
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
        m = re.match(r'^["\'](.*)["\']\s*$', val)
        if m:
            val = m.group(1)
        if key and re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', key):
            env[key] = val
    return env


# ── GitHub API helpers ────────────────────────────────────────────────────────
def auth_headers(token: str) -> dict:
    return {
        "Authorization":        f"Bearer {token}",
        "Accept":               "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }


def get_public_key(owner: str, repo: str, token: str) -> dict:
    url  = f"https://api.github.com/repos/{owner}/{repo}/actions/secrets/public-key"
    resp = requests.get(url, headers=auth_headers(token))
    resp.raise_for_status()
    return resp.json()


def list_existing_secrets(owner: str, repo: str, token: str) -> list[str]:
    """Return the names of secrets already set in the repo (values are never returned by API)."""
    url    = f"https://api.github.com/repos/{owner}/{repo}/actions/secrets"
    names  = []
    params = {"per_page": 100, "page": 1}
    while True:
        resp = requests.get(url, headers=auth_headers(token), params=params)
        resp.raise_for_status()
        data = resp.json()
        names += [s["name"] for s in data.get("secrets", [])]
        if len(data.get("secrets", [])) < 100:
            break
        params["page"] += 1
    return sorted(names)


def encrypt_secret(public_key_b64: str, secret_value: str) -> str:
    pub_key    = public.PublicKey(public_key_b64.encode("utf-8"), encoding.Base64Encoder())
    sealed_box = public.SealedBox(pub_key)
    encrypted  = sealed_box.encrypt(secret_value.encode("utf-8"))
    return base64.b64encode(encrypted).decode("utf-8")


def set_secret(owner: str, repo: str, token: str,
               name: str, value: str, key_id: str, key: str,
               dry_run: bool = False) -> bool:
    if dry_run:
        print(f"  [dry-run]  {name}")
        return True
    encrypted = encrypt_secret(key, value)
    url       = f"https://api.github.com/repos/{owner}/{repo}/actions/secrets/{name}"
    resp      = requests.put(
        url,
        headers=auth_headers(token),
        json={"encrypted_value": encrypted, "key_id": key_id},
    )
    ok = resp.status_code in (201, 204)
    if ok:
        print(f"  ✔  {name}")
    else:
        print(f"  ✘  {name}  [{resp.status_code}] {resp.text}")
    return ok


# ── Repo operations ───────────────────────────────────────────────────────────
def show_existing(owner: str, repo: str, token: str) -> None:
    print(f"\n{'='*60}")
    print(f"  {owner}/{repo}  — existing secrets")
    print(f"{'='*60}")
    try:
        names = list_existing_secrets(owner, repo, token)
        if names:
            for n in names:
                print(f"  •  {n}")
        else:
            print("  (no secrets set yet)")
    except requests.HTTPError as e:
        print(f"  ERROR: {e}")
    print(f"\n  Manage at: https://github.com/{owner}/{repo}/settings/secrets/actions")


def push_secrets(owner: str, repo: str, token: str,
                 secrets: dict, dry_run: bool = False) -> None:
    """Fetch repo public key then push all non-empty secrets."""
    print(f"\n{'='*60}")
    print(f"  {owner}/{repo}{'  [DRY RUN]' if dry_run else ''}")
    print(f"{'='*60}")

    if not secrets:
        print("  (nothing to push — all values are empty)")
        return

    if not dry_run:
        print("  Fetching repo public key...")
        try:
            pub_key_data = get_public_key(owner, repo, token)
        except requests.HTTPError as e:
            print(f"  ERROR: could not fetch public key — {e}")
            print("  Check your PAT has 'repo' scope and the repo name is correct.")
            return
        key_id = pub_key_data["key_id"]
        key    = pub_key_data["key"]
        print(f"  Public key: {key_id}\n")
    else:
        key_id = key = ""

    for name, value in secrets.items():
        set_secret(owner, repo, token, name, value, key_id, key, dry_run=dry_run)

    if not dry_run:
        print(f"\n  Verify at: https://github.com/{owner}/{repo}/settings/secrets/actions")


# ── Secret definitions ────────────────────────────────────────────────────────
def build_secret_maps(env: dict) -> tuple[dict, dict, dict, dict]:
    """
    Returns (platform_secrets, build_secrets, platform_required, build_required).
    Empty values and placeholder strings are excluded — they will be skipped.
    """
    platform_rg      = env.get("PLATFORM_RG",            "techwizard-platformlab-apps")
    platform_kv      = env.get("PLATFORM_KV_NAME",       "techwizard-plt-kv")
    shared_rg        = env.get("AZURE_SHARED_RG",        "my-Rental-App")
    tf_backend_rg    = env.get("TF_BACKEND_RG",          platform_rg)
    tf_backend_sa    = env.get("TF_BACKEND_SA",          "")
    acr_name         = env.get("ACR_NAME",               "")

    # Azure identifiers — fetch from Key Vault (not stored in .env)
    client_id       = kv_get_secret(platform_kv, "azure-client-id")
    tenant_id       = kv_get_secret(platform_kv, "azure-tenant-id")
    subscription_id = kv_get_secret(platform_kv, "azure-subscription-id")

    # NOTE: DISCORD_WEBHOOK_URL and ARGOCD_GITHUB_PAT are intentionally NOT pushed
    # as GitHub Secrets — workflows fetch them directly from Key Vault at runtime.
    smtp_password    = env.get("SMTP_PASSWORD",          "")
    mail_to          = env.get("MAIL_TO",                "")
    groq_api_key     = env.get("GROQ_API_KEY",           "")
    anthropic_key    = env.get("ANTHROPIC_API_KEY",      "")
    dockerhub_user   = env.get("DOCKERHUB_USERNAME",     "")
    dockerhub_token  = env.get("DOCKERHUB_TOKEN",        "")

    # Auto-derive ACR login server from name if not explicitly set
    acr_login_server = env.get("ACR_LOGIN_SERVER", "")
    if not acr_login_server and acr_name:
        acr_login_server = f"{acr_name}.azurecr.io"

    # ── Platform repo (AI-RentalApp-Ledger) ──────────────────────────────────
    platform_secrets = {
        # OIDC auth
        "AZURE_CLIENT_ID":       client_id,
        "AZURE_TENANT_ID":       tenant_id,
        "AZURE_SUBSCRIPTION_ID": subscription_id,
        # Terraform state backend (in techwizard-platformlab-apps)
        "TF_BACKEND_RG":         tf_backend_rg,
        "TF_BACKEND_SA":         tf_backend_sa,
        # TF_BACKEND_CONTAINER computed per-env: rentalapp-<env>-tfstate
        # Notifications (optional — DISCORD_WEBHOOK_URL fetched from KV at runtime)
        "SMTP_PASSWORD":         smtp_password,
        "MAIL_TO":               mail_to,
    }

    # ── Build repo (RentalApp-Build) ──────────────────────────────────────────
    build_secrets = {
        # OIDC auth
        "AZURE_CLIENT_ID":       client_id,
        "AZURE_TENANT_ID":       tenant_id,
        "AZURE_SUBSCRIPTION_ID": subscription_id,
        # Container registry — ACR name/server are env-specific (random suffix from Terraform)
        # Fetched at runtime from Key Vault secret: acr-login-server
        # Docker Hub
        "DOCKERHUB_USERNAME":    dockerhub_user,
        "DOCKERHUB_TOKEN":       dockerhub_token,
        # AI keys (optional)
        "GROQ_API_KEY":          groq_api_key,
        "ANTHROPIC_API_KEY":     anthropic_key,
    }

    # Required (must be set before first pipeline run)
    platform_required = {
        "AZURE_CLIENT_ID", "AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID",
        "TF_BACKEND_SA", "TF_BACKEND_RG",
    }
    platform_post_tf = set()

    build_required = {
        "AZURE_CLIENT_ID", "AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID",
    }

    def clean(d: dict) -> dict:
        return {k: v for k, v in d.items() if v and "<" not in v and v != ""}

    return (
        clean(platform_secrets),
        clean(build_secrets),
        platform_required,
        platform_post_tf,
        build_required,
    )


def warn_missing(label: str, secrets_set: dict,
                 required: set, post_tf: set = None) -> None:
    missing_required = required - set(secrets_set.keys())
    missing_post_tf  = (post_tf or set()) - set(secrets_set.keys())

    if missing_required:
        print(f"\n  ⚠  [{label}] Required secrets not yet set:")
        for k in sorted(missing_required):
            print(f"     - {k}")

    if missing_post_tf:
        print(f"\n  ℹ  [{label}] Set these after the shared Terraform apply:")
        for k in sorted(missing_post_tf):
            print(f"     - {k}  (run: terraform -chdir=infrastructure/azure/shared output)")


# ── CLI ───────────────────────────────────────────────────────────────────────
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Push GitHub Actions secrets to platform and/or build repo."
    )
    parser.add_argument(
        "--repo",
        choices=["platform", "build", "both"],
        default="both",
        help="Which repo to push to (default: both)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be set without making any changes",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List existing secret names in the target repos (no values shown)",
    )
    return parser.parse_args()


# ── Main ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    args     = parse_args()
    env_file = Path(__file__).parent / ".env"
    env      = load_env(env_file)

    owner         = env.get("GITHUB_ORG",  "Ramprasath26")
    platform_repo = env.get("GITHUB_REPO", "AI-RentalApp-Ledger")
    build_repo    = env.get("BUILD_REPO",  "RentalApp-Build")

    platform_secrets, build_secrets, plat_req, plat_post_tf, build_req = \
        build_secret_maps(env)

    # ── PAT: platform Key Vault → env var → interactive prompt ───────────────
    token = env.get("GITHUB_PAT", "").strip()

    if not token:
        # Try platform Key Vault first (shared across all apps)
        kv_name = env.get("PLATFORM_KV_NAME", "").strip()
        if kv_name and "<" not in kv_name:
            print(f"Fetching GITHUB_PAT from platform Key Vault: {kv_name} ...")
            token = kv_get_secret(kv_name, "github-pat")
            if token:
                print("  ✔  PAT loaded from Key Vault")
            else:
                print("  ⚠  PAT not found in Key Vault — falling back to interactive prompt")

    if not token:
        print("Enter your GitHub Personal Access Token (PAT)")
        print("  Scope required : repo  (classic token)")
        print("  Create one at  : https://github.com/settings/tokens/new")
        print("  Store in KV    : bash bootstrap/store-secrets.sh")
        print()
        token = getpass.getpass("PAT: ").strip()

    if not token:
        print("ERROR: No token provided. Exiting.")
        sys.exit(1)

    # ── List mode ─────────────────────────────────────────────────────────────
    if args.list:
        if args.repo in ("platform", "both"):
            show_existing(owner, platform_repo, token)
        if args.repo in ("build", "both"):
            show_existing(owner, build_repo, token)
        sys.exit(0)

    # ── Warn about missing secrets ────────────────────────────────────────────
    if args.repo in ("platform", "both"):
        warn_missing("platform", platform_secrets, plat_req, plat_post_tf)
    if args.repo in ("build", "both"):
        warn_missing("build", build_secrets, build_req)

    # ── Push ──────────────────────────────────────────────────────────────────
    if args.repo in ("platform", "both"):
        push_secrets(owner, platform_repo, token, platform_secrets, dry_run=args.dry_run)
    if args.repo in ("build", "both"):
        push_secrets(owner, build_repo, token, build_secrets, dry_run=args.dry_run)

    print("\nDone.")
