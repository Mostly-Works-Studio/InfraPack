#!/usr/bin/env python3
"""InfraPack console — status dashboard, catalog and settings editor.

Serves a small web UI that shows every installed tech, its ports, links and
credentials, lets you install more from the catalog, and edits settings
without touching .env by hand. Every action is delegated to the `infrapack`
CLI so the terminal and the console can never disagree.
"""
import json
import os
import re
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import registry as reg  # noqa: E402

HOME = reg.HOME
APP = reg.APP
ENV_PATH = HOME / ".env"
STACKS_DIR = reg.STACKS_DIR
STATIC = Path(__file__).parent / "static"
PORT = int(os.environ.get("CONSOLE_INTERNAL_PORT", "8000"))
VERSION = os.environ.get("INFRAPACK_VERSION", "dev")
HOST_OS = os.environ.get("INFRAPACK_HOST_OS", "unknown")
PROJECT = "infrapack"
CLI = ["bash", str(APP / "bin" / "infrapack")]


# ------------------------------------------------------------- host agent --
# Docker Desktop is a macOS app, so this container cannot restart it directly.
# `infrapack agent install` puts a launchd agent on the host that watches
# $INFRAPACK_HOME/inbox/request; writing an action there is how we ask.
def agent_installed():
    return (HOME / "installed").exists()


def agent_request(action):
    inbox = HOME / "inbox"
    inbox.mkdir(parents=True, exist_ok=True)
    tmp = inbox / "request.tmp"
    tmp.write_text(action)
    tmp.replace(inbox / "request")     # atomic, so launchd sees a complete file


def agent_status():
    f = HOME / "status"
    if not f.exists():
        return None
    parts = f.read_text().strip().split("\t")
    return {"at": parts[0], "result": parts[1], "message": parts[2]} if len(parts) == 3 else None


# ---------------------------------------------------------------- fields --
CORE_FIELDS = [
    {"key": "CONSOLE_PORT", "label": "Console port", "type": "port", "stack": "console", "group": "Console"},
    {"key": "INFRA_RESTART", "label": "Techs auto-start with Docker", "type": "choice",
     "choices": ["no", "unless-stopped"], "stack": "console", "group": "Console"},
]


def fields():
    """Editable .env keys: whatever the installed stacks declare, plus the
    console's own. Anything not listed here is rejected by the API."""
    out = []
    for stack in reg.load_all():
        for setting in stack["settings"]:
            out.append({**setting, "type": setting.get("type", "text"),
                        "stack": stack["stack"], "group": setting.get("group", stack["label"])})
    out.extend(CORE_FIELDS)
    return out


def stack_names():
    return [s["stack"] for s in reg.load_all()]


def service_names():
    return [sv for s in reg.load_all() for sv in s["compose_services"]]


def cards(env):
    """Service cards, grouped by stack, in registry order."""
    out = []
    for stack in reg.load_all():
        for sv in stack["services"]:
            facts = [dict(f, value=reg.expand(f.get("value", ""), env)) for f in sv.get("facts", [])]
            out.append({
                "key": sv["name"],
                "stack": stack["stack"],
                "stackLabel": stack["label"],
                "name": sv.get("label", sv["name"]),
                "container": f"{PROJECT}-{sv['name']}",
                "desc": reg.expand(sv.get("desc", ""), env),
                "link": reg.expand(sv["link"], env) if sv.get("link") else None,
                "ui": sv["ui"],
                "custom": stack["custom"],
                "facts": facts,
            })
    return out


# --------------------------------------------------------- stack authoring --
# Lives in stackgen.py so `infrapack add` (run inside this image) and the web
# form share one implementation.
import stackgen  # noqa: E402

STACK_NAME_RE = stackgen.STACK_NAME_RE


# -------------------------------------------------------------- env file ---
ENV_LINE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$")


def read_env():
    return reg.read_env()


def _quote(value):
    return f'"{value}"' if (" " in value or value == "") else value


def write_env(updates):
    """Rewrite .env in place, preserving comments, order and formatting."""
    lines = ENV_PATH.read_text().splitlines() if ENV_PATH.exists() else []
    seen, out = set(), []
    for line in lines:
        m = ENV_LINE.match(line)
        if m and not line.lstrip().startswith("#") and m.group(1) in updates:
            out.append(f"{m.group(1)}={_quote(updates[m.group(1)])}")
            seen.add(m.group(1))
        else:
            out.append(line)
    for key, value in updates.items():
        if key not in seen:
            out.append(f"{key}={_quote(value)}")
    ENV_PATH.write_text("\n".join(out) + "\n")


def validate(updates):
    """Return a list of human-readable problems."""
    problems = []
    by_key = {f["key"]: f for f in fields()}
    env = read_env()
    merged = {**env, **updates}
    for key, value in updates.items():
        f = by_key.get(key)
        if not f:
            problems.append(f"{key} is not an editable setting")
            continue
        if "\n" in value or "\r" in value:
            problems.append(f"{key} must be a single line")
        kind = f["type"]
        if kind in ("port", "int"):
            if not value.isdigit():
                problems.append(f"{f['group']} {f['label'].lower()} must be a number")
            elif kind == "port" and not (1 <= int(value) <= 65535):
                problems.append(f"{f['group']} {f['label'].lower()} must be between 1 and 65535")
        if kind in ("text", "secret") and value.strip() == "" and not f.get("optional"):
            problems.append(f"{f['group']} {f['label'].lower()} cannot be empty")
        if kind == "choice" and value not in f.get("choices", []):
            problems.append(f"{key} must be one of {', '.join(f.get('choices', []))}")
        if f.get("pattern") and not re.fullmatch(f["pattern"], value):
            problems.append(f"{f['group']} {f['label'].lower()} has characters that are not allowed")
    ports = {}
    for f in fields():
        if f["type"] == "port":
            ports.setdefault(merged.get(f["key"], ""), []).append(f"{f['group']} {f['label'].lower()}")
    for value, keys in ports.items():
        if len(keys) > 1:
            problems.append(f"port {value} is used by both {' and '.join(keys)}")
    return problems


# --------------------------------------------------------------- docker ----
def run(cmd, cwd=HOME, timeout=600, extra_env=None):
    try:
        env = {**os.environ, **(extra_env or {})}
        p = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True,
                           timeout=timeout, env=env)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, "timed out"
    except Exception as exc:                      # noqa: BLE001
        return 1, str(exc)


def infra(*args, detached=False, extra_env=None):
    """Run the CLI. `detached` runs it in a throwaway sidecar container, for
    actions that recreate this very container (moving the console's port)."""
    if detached:
        image = os.environ.get("INFRAPACK_IMAGE", "ghcr.io/mostly-works-studio/infrapack") + ":" + VERSION
        sock = os.environ.get("DOCKER_SOCK", "/var/run/docker.sock")
        cmd = ["docker", "run", "-d", "--rm", "--name", f"{PROJECT}-sidecar-{int(time.time())}",
               "-v", f"{sock}:/var/run/docker.sock", "-v", f"{HOME}:{HOME}",
               "-e", f"INFRAPACK_HOME={HOME}", "-e", f"INFRAPACK_HOST_OS={HOST_OS}",
               "-e", f"DOCKER_SOCK={sock}", "-e", "NO_COLOR=1", image, "bash", "/app/bin/infrapack", *args]
        return run(cmd, timeout=60)
    return run([*CLI, *args], extra_env={"NO_COLOR": "1", **(extra_env or {})})


HEALTH = re.compile(r"\((healthy|unhealthy|health: starting|starting)\)")


def container_states():
    code, out = run(["docker", "ps", "-a", "--filter", f"name={PROJECT}-",
                     "--format", "{{.Names}}\t{{.State}}\t{{.Status}}"], timeout=20)
    states = {}
    if code == 0:
        for line in out.strip().splitlines():
            parts = line.split("\t")
            if len(parts) != 3:
                continue
            name, state, status = parts
            m = HEALTH.search(status)
            states[name] = {"state": state, "status": status,
                            "health": (m.group(1).replace("health: ", "") if m else None)}
    return states


def state_payload():
    env = read_env()
    states = container_states()
    svc_cards = cards(env)
    for card in svc_cards:
        info = states.get(card["container"])
        card["state"] = info["state"] if info else "absent"
        card["health"] = info["health"] if info else None
        card["status"] = info["status"] if info else "not created"
        card["up"] = bool(info and info["state"] == "running")
    snap = snapshot()
    for card in svc_cards:
        card["usage"] = snap["services"].get(card["key"]) if card["up"] else None
    field_list = [{**f, "value": env.get(f["key"], "")} for f in fields()]
    stacks = [{"name": s["stack"], "label": s["label"], "blurb": s["blurb"],
               "category": s["category"], "custom": s["custom"],
               "services": s["compose_services"], "hasCommands": s["has_commands"]}
              for s in reg.load_all()]
    return {"services": svc_cards, "fields": field_list, "stacks": stacks,
            "consolePort": env.get("CONSOLE_PORT", "7070"),
            "version": VERSION, "hostOS": HOST_OS, "home": str(HOME),
            "dockerControl": agent_installed() and HOST_OS == "Darwin",
            "agentStatus": agent_status(),
            "docker": snap["vm"], "usage": snap["totals"], "sampledAt": snap["at"]}


# `docker stats` takes ~2s, so it is sampled on a timer and served from cache.
SAMPLE_INTERVAL = 5
_sample = {"at": 0, "services": {}, "vm": None, "totals": None}
_sample_lock = threading.Lock()
_UNITS = {"B": 1 / 1024 ** 2, "KiB": 1 / 1024, "MiB": 1.0, "GiB": 1024.0, "TiB": 1024.0 ** 2}


def _to_mb(text):
    m = re.match(r"([\d.]+)\s*([KMGT]iB|B)", text.strip())
    return round(float(m.group(1)) * _UNITS[m.group(2)], 1) if m else None


def read_vm():
    code, out = run(["docker", "info", "--format", "{{.NCPU}}\t{{.MemTotal}}\t{{.OperatingSystem}}\t{{.Architecture}}"], timeout=20)
    if code != 0 or "\t" not in out:
        return None
    cpus, mem, engine, arch = (out.strip().split("\t") + ["", "", "", ""])[:4]
    platform = {"aarch64": "linux/arm64", "arm64": "linux/arm64", "x86_64": "linux/amd64", "amd64": "linux/amd64"}.get(arch, f"linux/{arch}")
    try:
        return {"cpus": int(cpus), "memMB": round(int(mem) / 1024 ** 2, 1),
                "memGiB": round(int(mem) / 1024 ** 3, 1), "engine": engine, "platform": platform}
    except ValueError:
        return None


def read_stats():
    code, out = run(["docker", "stats", "--no-stream", "--format",
                     "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"], timeout=30)
    result = {}
    if code != 0:
        return result
    for line in out.strip().splitlines():
        parts = line.split("\t")
        if len(parts) < 3 or not parts[0].startswith(f"{PROJECT}-"):
            continue
        name, cpu, mem = parts[0], parts[1], parts[2]
        try:
            cpu_val = float(cpu.strip().rstrip("%"))
        except ValueError:
            continue
        result[name[len(PROJECT) + 1:]] = {"cpu": round(cpu_val, 2), "memMB": _to_mb(mem.split("/")[0])}
    return result


def sampler():
    while True:
        try:
            vm = read_vm()
            stats = read_stats()
            totals = {"cpu": round(sum(v["cpu"] for v in stats.values()), 2),
                      "memMB": round(sum(v["memMB"] or 0 for v in stats.values()), 1),
                      "count": len([k for k in stats if k != "console"])}
            with _sample_lock:
                _sample.update({"at": time.time(), "services": stats, "vm": vm, "totals": totals})
        except Exception:                          # noqa: BLE001 — never kill the thread
            pass
        time.sleep(SAMPLE_INTERVAL)


def snapshot():
    with _sample_lock:
        return dict(_sample)


# ----------------------------------------------------------------- server --
class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        if os.environ.get("CONSOLE_DEBUG"):
            super().log_message(fmt, *args)

    def _send(self, code, body, ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            return {}

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/state":
            return self._send(200, state_payload())
        if path == "/api/catalog":
            env = read_env()
            out = []
            for e in reg.catalog():
                core = next((s for s in e["services"] if not s["ui"]), None)
                uis = [s for s in e["services"] if s["ui"]]
                out.append({"name": e["stack"], "label": e["label"], "blurb": e["blurb"],
                            "category": e["category"], "installed": e["installed"],
                            "platform": e.get("platform"),
                            "ports": e["ports"], "uiLabel": uis[0]["label"] if uis else None,
                            "desc": reg.expand(core.get("desc", ""), e["defaults"]) if core else "",
                            "services": e["compose_services"]})
            return self._send(200, out)
        if path in ("/", "/index.html"):
            return self._send(200, (STATIC / "index.html").read_bytes(), "text/html; charset=utf-8")
        if path == "/api/export":
            code, out = run(["python3", str(APP / "console" / "pack.py"), "export"] +
                            (["--with-secrets"] if "secrets=1" in self.path else []), timeout=30)
            if code != 0:
                return self._send(500, {"error": out[-500:]})
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Disposition", 'attachment; filename="infrapack-export.json"')
            self.send_header("Content-Length", str(len(out.encode())))
            self.end_headers()
            self.wfile.write(out.encode())
            return
        if path == "/healthz":
            return self._send(200, {"ok": True, "version": VERSION})
        return self._send(404, {"error": "not found"})

    def do_POST(self):
        path = self.path.split("?")[0]
        body = self._body()

        if path == "/api/action":
            action = body.get("action")
            stacks = [s for s in body.get("stacks", []) if s in stack_names()]
            if action not in ("up", "down", "restart") or not stacks:
                return self._send(400, {"error": "bad request"})
            code, out = infra(action, *stacks)
            return self._send(200, {"ok": code == 0, "output": out.strip()[-4000:]})

        if path == "/api/service":
            action, service = body.get("action"), body.get("service")
            if action not in ("up", "down", "restart") or service not in service_names():
                return self._send(400, {"error": "bad request"})
            code, out = infra("svc", action, service)
            return self._send(200, {"ok": code == 0, "output": out.strip()[-4000:]})

        if path == "/api/save":
            updates = {k: str(v) for k, v in (body.get("values") or {}).items()}
            current = read_env()
            changed = {k: v for k, v in updates.items() if current.get(k) != v}
            if not changed:
                return self._send(200, {"ok": True, "changed": [], "output": "nothing to change"})
            problems = validate(changed)
            if problems:
                return self._send(400, {"error": "; ".join(problems)})
            write_env(changed)
            by_key = {f["key"]: f["stack"] for f in fields()}
            touched = {by_key[k] for k in changed}
            msg = []
            self_restart = "console" in touched
            targets = [s for s in stack_names() if s in touched]
            if body.get("apply", True) and targets:
                # Hooks get the previous values as OLD_<KEY>, for techs that
                # only read their config at first boot (MySQL credentials).
                old = {f"OLD_{k}": current.get(k, "") for k in changed}
                code, out = infra("apply", *targets, extra_env=old)
                msg.append(out.strip()[-4000:])
                if code == 3:
                    # containers were recreated, only the tech's own fix-up failed:
                    # keep the new settings so the user can retry rather than revert
                    return self._send(200, {"ok": False, "changed": sorted(changed), "output": "\n".join(msg)})
                if code != 0:
                    write_env({k: current.get(k, "") for k in changed})
                    msg.append("reverted the settings — nothing changed")
                    return self._send(200, {"ok": False, "changed": [], "output": "\n".join(msg)})
            new_port = None
            if self_restart:
                new_port = read_env().get("CONSOLE_PORT")
                infra("apply", "console", detached=True)
                msg.append(f"console moving to port {new_port}")
            return self._send(200, {"ok": True, "changed": sorted(changed),
                                    "consolePort": new_port, "output": "\n".join(msg)})

        if path == "/api/stacks/install":
            name = str(body.get("name", ""))
            if not STACK_NAME_RE.match(name):
                return self._send(400, {"error": "bad name"})
            sets = []
            for k, v in (body.get("settings") or {}).items():
                if not re.fullmatch(r"[A-Z][A-Z0-9_]*", str(k)) or "\n" in str(v):
                    return self._send(400, {"error": f"bad setting {k}"})
                sets.append(f"{k}={v}")
            code, out = infra("install", name, *sets)
            return self._send(200, {"ok": code == 0, "stack": name, "output": out.strip()[-4000:]})

        if path in ("/api/stacks/add", "/api/stacks/import"):
            dry_run = bool(body.get("dryRun"))
            try:
                if path.endswith("import"):
                    name = str(body.get("name", "")).strip().lower()
                    body = stackgen.spec_from_compose(name, str(body.get("compose", "")), body.get("label"))
                spec = stackgen.build_spec(body)
            except stackgen.SpecError as exc:
                return self._send(400, {"error": str(exc)})
            if dry_run:
                return self._send(200, {"ok": True, "compose": stackgen.render_compose(spec), "env": spec["env"]})
            taken = {}
            for f in fields():
                if f["type"] == "port":
                    taken[read_env().get(f["key"])] = f["group"]
            for key, value in spec["env"].items():
                if re.search(r"_PORT\d*$", key) and value in taken:
                    return self._send(400, {"error": f"port {value} is already used by {taken[value]}"})
            stackgen.write_stack(spec)
            # the CLI merges the defaults into .env, checks ports and starts it
            code, out = infra("_finish-install", spec["stack"])
            if code != 0:
                return self._send(200, {"ok": False, "stack": spec["stack"],
                                        "output": out.strip()[-4000:] + "\nrolled back — nothing was added"})
            return self._send(200, {"ok": True, "stack": spec["stack"], "output": out.strip()[-3000:]})

        if path == "/api/stacks/remove":
            name = str(body.get("name", ""))
            if reg.by_name(name) is None:
                return self._send(400, {"error": "no such stack"})
            args = ["uninstall", name] + (["--purge"] if body.get("purge") else [])
            code, out = infra(*args)
            return self._send(200, {"ok": code == 0, "output": out.strip()[-2000:]})

        if path == "/api/import":
            data = body.get("data")
            if not isinstance(data, (dict, str)):
                return self._send(400, {"error": "send the export file's contents as 'data'"})
            tmp = HOME / ".import.json"
            tmp.write_text(data if isinstance(data, str) else json.dumps(data))
            try:
                code, out = infra("import", str(tmp), "--yes", *(["--force"] if body.get("force") else []))
            finally:
                tmp.unlink(missing_ok=True)
            return self._send(200, {"ok": code == 0, "output": out.strip()[-4000:]})

        if path == "/api/docker":
            if body.get("action") != "restart":
                return self._send(400, {"error": "only 'restart' is supported"})
            if not agent_installed():
                return self._send(400, {"error": "host agent not installed — run 'infrapack agent install'"})
            agent_request("restart-docker")
            return self._send(200, {"ok": True, "output": "restart requested"})

        if path == "/api/logs":
            service = body.get("service")
            if service not in service_names() and service != "console":
                return self._send(400, {"error": "bad request"})
            code, out = run(["docker", "logs", "--tail", str(int(body.get("tail") or 200)),
                             f"{PROJECT}-{service}"], timeout=20)
            return self._send(200, {"ok": code == 0, "output": out[-60000:]})

        return self._send(404, {"error": "not found"})


def main():
    if not ENV_PATH.exists():
        print(f"warning: {ENV_PATH} not found — is INFRAPACK_HOME correct?", file=sys.stderr)
    threading.Thread(target=sampler, daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True
    print(f"InfraPack console {VERSION} listening on :{PORT} (workspace {HOME})")
    server.serve_forever()


if __name__ == "__main__":
    main()
