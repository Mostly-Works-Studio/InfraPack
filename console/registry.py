#!/usr/bin/env python3
"""Stack registry — what is installed, what is in the catalog.

A stack is a directory:

  compose.yml     compose fragment (services, volumes)
  stack.json      how the console presents it: labels, links, facts, settings
  defaults.env    settings appended to .env on install
  hooks/*.sh      optional lifecycle hooks (pre-up, post-up, post-settings…)
  commands.sh     optional `infrapack <stack> <cmd>` helpers

Installed stacks live in $INFRAPACK_HOME/stacks, catalog entries in
$INFRAPACK_APP/catalog. The CLI (bash) reads the same directories with grep
and awk; this module is what the console and JSON-shaped CLI verbs use.

Conventions:
  - the core service is named after the stack; a web UI is <stack>-ui
  - containers are named infrapack-<service>
  - env keys are <STACK>_PORT, <STACK>_VERSION, <STACK>_UI_PORT, …
"""
import json
import os
import re
import sys
from pathlib import Path

HOME = Path(os.environ.get("INFRAPACK_HOME") or Path.home() / ".infrapack")
APP = Path(os.environ.get("INFRAPACK_APP") or Path(__file__).resolve().parent.parent)
STACKS_DIR = HOME / "stacks"
CATALOG_DIR = APP / "catalog"

NAME_RE = re.compile(r"^[a-z][a-z0-9-]{1,23}$")
VAR_RE = re.compile(r"\{([A-Z][A-Z0-9_]*)\}")
SERVICE_RE = re.compile(r"^  ([A-Za-z0-9_.-]+):\s*$")


def _load_dir(path):
    """One stack definition from a directory, or None if it is not one."""
    meta_file, compose = path / "stack.json", path / "compose.yml"
    if not compose.exists():
        return None
    try:
        data = json.loads(meta_file.read_text()) if meta_file.exists() else {}
    except (json.JSONDecodeError, OSError) as exc:
        print(f"registry: skipping {path.name}: {exc}", file=sys.stderr)
        return None
    name = data.get("stack") or path.name
    if not NAME_RE.match(name):
        print(f"registry: skipping {path.name}: bad stack name", file=sys.stderr)
        return None
    data["stack"] = name
    data["dir"] = str(path)
    data.setdefault("label", name.title())
    data.setdefault("blurb", "")
    data.setdefault("category", "other")
    data.setdefault("settings", [])
    data["custom"] = bool(data.get("custom", False))
    data["defaults"] = read_env_file(path / "defaults.env")
    data["compose_services"] = compose_service_names(compose)
    # Presentation entries default to one per compose service.
    services = data.get("services") or [{"name": s} for s in data["compose_services"]]
    for svc in services:
        svc.setdefault("label", svc["name"])
        svc.setdefault("facts", [])
        svc["ui"] = bool(svc.get("ui", svc["name"].endswith("-ui")))
    data["services"] = services
    data["has_commands"] = (path / "commands.sh").exists()
    return data


def _load_from(root):
    out = []
    if not root.is_dir():
        return out
    for path in sorted(root.iterdir()):
        if path.is_dir():
            data = _load_dir(path)
            if data:
                out.append(data)
    return out


def load_all():
    """Installed stacks, by name."""
    return _load_from(STACKS_DIR)


def catalog():
    """Catalog entries, flagged with whether they are already installed."""
    installed = {s["stack"] for s in load_all()}
    out = _load_from(CATALOG_DIR)
    for entry in out:
        entry["installed"] = entry["stack"] in installed
        entry["ports"] = {k: v for k, v in entry["defaults"].items() if k.endswith("_PORT")}
    return out


def by_name(name):
    for s in load_all():
        if s["stack"] == name:
            return s
    return None


def compose_service_names(compose_path):
    names, in_services = [], False
    try:
        lines = compose_path.read_text().splitlines()
    except OSError:
        return names
    for line in lines:
        if re.match(r"^services:\s*$", line):
            in_services = True
            continue
        if line and not line[0].isspace() and not line.startswith("#"):
            in_services = False
        if in_services:
            m = SERVICE_RE.match(line)
            if m:
                names.append(m.group(1))
    return names


def core_services(stack):
    return [s for s in stack["compose_services"] if not s.endswith("-ui")]


def ui_services(stack):
    return [s for s in stack["compose_services"] if s.endswith("-ui")]


def expand(text, env):
    """Replace {VAR} with the value from .env, leaving unknown vars visible."""
    return VAR_RE.sub(lambda m: env.get(m.group(1), m.group(0)), str(text))


def read_env_file(path):
    env = {}
    if path.exists():
        for line in path.read_text().splitlines():
            if line.lstrip().startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            v = v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            env[k.strip()] = v
    return env


def read_env():
    return read_env_file(HOME / ".env")


def urls(stack, running):
    """Connection details for a stack, for `infrapack urls`."""
    env = read_env()
    out = []
    for svc in stack["services"]:
        if svc["name"] not in running:
            continue
        label = svc.get("label", svc["name"])
        first = True
        if svc.get("link"):
            out.append(f"  {label:<14} {expand(svc['link'], env)}")
            first = False
        shown = 0
        for fact in svc.get("facts", []):
            if not fact.get("copy") or fact.get("secret") or shown >= 3:
                continue
            out.append(f"  {label if first else '':<14} {fact['label']}: {expand(fact['value'], env)}")
            first = False
            shown += 1
    return out


# ------------------------------------------------------------------ CLI ----
def main(argv):
    cmd = argv[1] if len(argv) > 1 else "stacks"
    arg = argv[2] if len(argv) > 2 else None

    if cmd == "stacks":
        print(" ".join(s["stack"] for s in load_all()))
        return 0
    if cmd == "catalog":
        print(json.dumps(catalog(), indent=2))
        return 0
    if cmd == "json":
        print(json.dumps(load_all(), indent=2))
        return 0

    stack = by_name(arg) if arg else None
    if stack is None:
        print(f"no such stack: {arg}", file=sys.stderr)
        return 1
    if cmd == "services":
        print(" ".join(stack["compose_services"]))
    elif cmd == "urls":
        for line in urls(stack, set(argv[3:])):
            print(line)
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
