#!/usr/bin/env python3
"""Workspace export/import — one shareable file for a whole team.

  pack.py export [--with-secrets]     workspace -> JSON on stdout
  pack.py import [--force]            JSON on stdin -> custom stack dirs written,
                                      then a line-oriented plan on stdout for
                                      the CLI to act on:
                                        CUSTOM <name>        (written, needs finishing)
                                        INSTALL <name>       (catalog entry to install)
                                        SKIP <name> <why>
                                        SET <KEY>=<value>    (settings to apply)

The file carries every installed tech (catalog ones by name, custom ones with
their files) and the settings. Secrets are masked unless --with-secrets.
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import registry as reg  # noqa: E402

FORMAT = 1
SECRET_RE = re.compile(r"(PASSWORD|SECRET|TOKEN|_KEY$|APIKEY|PASS$)", re.I)
CORE_KEYS = {"TZ", "CONSOLE_PORT", "CONSOLE_RESTART", "INFRA_RESTART"}
# Files that make up a custom stack; anything else in its directory is
# generated state (e.g. a rendered config) and is not shipped.
SHIPPED = ("compose.yml", "stack.json", "defaults.env", "commands.sh")


def _is_secret(key, stack):
    for s in stack.get("settings", []):
        if s["key"] == key:
            return s.get("type") == "secret"
    return bool(SECRET_RE.search(key))


def export(with_secrets=False):
    env = reg.read_env()
    catalog = {c["stack"] for c in reg.catalog()}
    out = {"infrapack": FORMAT, "settings": {}, "techs": []}
    for key in CORE_KEYS:
        if key in env and key != "CONSOLE_PORT":
            out["settings"][key] = env[key]
    for stack in reg.load_all():
        name = stack["stack"]
        entry = {"name": name, "custom": bool(stack["custom"] or name not in catalog), "settings": {}}
        for key in stack["defaults"]:
            if key not in env:
                continue
            if _is_secret(key, stack) and not with_secrets:
                entry["settings"][key] = None       # "keep the default"
            else:
                entry["settings"][key] = env[key]
        if entry["custom"]:
            d = Path(stack["dir"])
            entry["files"] = {}
            for rel in SHIPPED:
                f = d / rel
                if f.exists():
                    entry["files"][rel] = f.read_text()
            for f in sorted((d / "hooks").glob("*.sh")) if (d / "hooks").is_dir() else []:
                entry["files"][f"hooks/{f.name}"] = f.read_text()
            for f in sorted((d / "files").rglob("*")) if (d / "files").is_dir() else []:
                if f.is_file() and f.stat().st_size < 256 * 1024:
                    entry["files"][str(f.relative_to(d))] = f.read_text(errors="replace")
        out["techs"].append(entry)
    return out


def do_import(data, force=False):
    if not isinstance(data, dict) or data.get("infrapack") != FORMAT:
        raise ValueError("not an InfraPack export (missing or unknown format marker)")
    installed = {s["stack"] for s in reg.load_all()}
    catalog = {c["stack"] for c in reg.catalog()}
    plan = []
    for key, value in (data.get("settings") or {}).items():
        if key in CORE_KEYS and value is not None:
            plan.append(f"SET {key}={value}")
    for tech in data.get("techs") or []:
        name = str(tech.get("name", ""))
        if not reg.NAME_RE.match(name):
            plan.append(f"SKIP {name} bad-name")
            continue
        if name in installed and not force:
            plan.append(f"SKIP {name} already-installed")
            continue
        if tech.get("custom"):
            files = tech.get("files") or {}
            if "compose.yml" not in files:
                plan.append(f"SKIP {name} no-compose")
                continue
            d = reg.STACKS_DIR / name
            for rel, text in files.items():
                if ".." in rel or rel.startswith("/") or not isinstance(text, str):
                    continue
                target = d / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text)
                if rel.endswith(".sh"):
                    target.chmod(0o755)
            plan.append(f"CUSTOM {name}")
        elif name in catalog:
            plan.append(f"INSTALL {name}")
        else:
            plan.append(f"SKIP {name} not-in-catalog")
            continue
        for key, value in (tech.get("settings") or {}).items():
            if value is None or not re.fullmatch(r"[A-Z][A-Z0-9_]*", str(key)) or "\n" in str(value):
                continue
            plan.append(f"SET {key}={value}")
    return plan


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    flags = set(argv[2:])
    if cmd == "export":
        print(json.dumps(export("--with-secrets" in flags), indent=2))
        return 0
    if cmd == "import":
        try:
            data = json.loads(sys.stdin.read() or "{}")
            for line in do_import(data, "--force" in flags):
                print(line)
        except (ValueError, OSError) as exc:
            print(f"ERROR {exc}")
            return 2
        return 0
    print(__doc__, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
