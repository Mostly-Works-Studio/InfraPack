# InfraPack

Local development infrastructure, one command. Install the techs your project
needs (databases, brokers, caches…), each with a web UI and copy-ready
connection strings, and turn them on and off from a terminal or a browser.

The only thing a machine needs is **Docker** and **bash**. No Python, no Node,
no package managers.

```
infrapack catalog              # what can be installed
infrapack install postgres     # add PostgreSQL + pgweb, start it
infrapack install kafka        # Kafka 4 (KRaft) + Kafka UI
infrapack status               # what is running, health, ports
infrapack urls                 # connection strings + UI links
infrapack open                 # the web console
infrapack down                 # stop everything, keep data
```

## Install

**Homebrew** (macOS, Linux):

```bash
brew tap mostly-works-studio/tap
brew trust mostly-works-studio/tap   # newer Homebrew asks once for third-party taps
brew install infrapack               # later: brew upgrade infrapack
```

**One line** (macOS, Linux):

```bash
curl -fsSL https://raw.githubusercontent.com/Mostly-Works-Studio/infrapack/master/install.sh | bash
```

Either way, then:

```bash
infrapack doctor          # checks Docker, ports, the console
infrapack open            # starts and opens the console
```

Docker is the one prerequisite: Docker Desktop, OrbStack or Colima on macOS,
Docker Engine with the compose plugin on Linux. The installer tells you how to
get it if it is missing. Update later with `infrapack update` (or
`brew upgrade infrapack`).

From a checkout (for development): `export PATH="$PWD/bin:$PATH"` and
`infrapack rebuild` once.

## How it fits together

```
app dir (this checkout / brew libexec)     workspace: ~/.infrapack
├── bin/infrapack        the CLI (bash)     ├── .env            every setting
├── catalog/<tech>/      installable techs  ├── stacks/<tech>/  installed techs
├── console/             web console        └── inbox/, agent.sh (macOS helper)
└── compose.yml          console + network
```

Every tech, in the catalog or installed, is a directory:

| file           | purpose                                                     |
|----------------|-------------------------------------------------------------|
| `compose.yml`  | the compose fragment (services, volumes)                    |
| `stack.json`   | how the console presents it: labels, links, facts, settings |
| `defaults.env` | settings appended to `.env` on install                      |
| `hooks/*.sh`   | optional: `pre-up`, `post-up`, `post-settings`, `post-install`, `pre-uninstall` |
| `commands.sh`  | optional: `infrapack <tech> <command>` helpers               |

`stack.json` may also declare `"platform": "linux/amd64"` for images that exist
for one CPU architecture only. On other machines `install` first checks that
emulation works (Rosetta, QEMU or binfmt), warns that it will be slower, and
the console marks the card *emulated*.

`install` copies the directory into the workspace and merges its defaults into
`.env`; `uninstall` reverses both. Ports are checked for clashes before
anything starts.

Conventions: the core service is named after the tech, its web UI is
`<tech>-ui`, containers are `infrapack-<service>`, env keys are
`<TECH>_PORT`, `<TECH>_VERSION`, `<TECH>_UI_PORT` and so on.

## The console

`infrapack open` → <http://localhost:7070>, bound to loopback only because it
controls Docker.

- **Installed** — every service with state, health, live CPU/memory, links and
  credentials (masked until revealed, copy buttons everywhere); per-service
  start/stop/restart toggles, per-tech start/stop/uninstall
- **Catalog** — install a tech with its ports pre-filled and editable, or
  define a **custom** tech from any image (ports, volume, command, env, an
  optional UI image)
- **Settings** — edit ports, credentials and image tags; save recreates only
  the affected containers and runs the tech's `post-settings` hook (MySQL
  applies credential changes to the running server and re-points CloudBeaver)
- **Logs** — the last lines of any container
- **Docker** — engine, VM size, usage and headroom; restart Docker Desktop
  from here on macOS once `infrapack agent install` has been run

Keyboard: **⌘S / Ctrl+S** saves, **Esc** discards or re-hides secrets,
**Enter** submits the install form.

The console runs in a container and drives the same `infrapack` CLI you use,
so the two can never disagree.

## Commands

```
Everyday
  up [tech...]         start installed techs (default: all) and the console
  down [tech...]       stop (data kept); no args = all techs, "all" = console too
  restart [tech...]    stop + start
  status               what is running, health, ports
  urls                 connection strings and UI links
  logs [service]       tail logs
  open                 open the web console

Techs
  catalog              what can be installed
  install <name>       add a tech        infrapack install redis REDIS_PORT=6380
  uninstall <name>     remove it (--purge deletes its data too)
  <tech> <command>     tech helpers      infrapack kafka topics · infrapack mysql shell

Settings
  config               show settings (secrets masked)
  config set K=V...    change settings and apply them
  reset [tech...]      stop and DELETE the data volumes
  pull [tech...]       refresh images

System
  doctor               check Docker, ports, the console
  update               update InfraPack itself
  agent <sub>          install|uninstall|status — Docker Desktop restart helper (macOS)
  exec <service> [cmd] shell into a container
  rebuild              rebuild the console image from source
  version

Flags:  --no-ui   start/stop core services only, without their web UIs
```

## Catalog

| category | tech | services | default ports |
|---|---|---|---|
| Databases | `cassandra` | Cassandra | main 9042 |
| Databases | `clickhouse` | ClickHouse | main 8123 · native 9010 |
| Databases | `mongo` | MongoDB, Mongo Express | main 27017 · ui 8083 |
| Databases | `mssql` | SQL Server (amd64 image; emulated on ARM) | main 1433 |
| Databases | `mysql` | MySQL, CloudBeaver | main 3306 · ui 8978 |
| Databases | `neo4j` | Neo4j | bolt 7687 · ui 7474 |
| Databases | `postgres` | PostgreSQL, pgweb | main 5432 · ui 8082 |
| Caches | `memcached` | Memcached | main 11211 |
| Caches | `redis` | Redis, RedisInsight | main 6379 · ui 5540 |
| Messaging & streaming | `kafka` | Kafka, Kafka UI | main 9092 · ui 8081 |
| Messaging & streaming | `nats` | NATS | main 4222 · monitor 8222 |
| Messaging & streaming | `rabbitmq` | RabbitMQ | main 5672 · ui 15672 |
| Search | `elasticsearch` | Elasticsearch, Kibana | main 9200 · ui 5601 |
| Search | `opensearch` | OpenSearch, OpenSearch Dashboards | main 9201 · ui 5602 |
| Object storage | `minio` | MinIO | main 9000 · ui 9001 |
| Cloud emulators | `dynamodb` | DynamoDB Local, dynamodb-admin | main 8000 · ui 8001 |
| Cloud emulators | `localstack` | LocalStack | main 4566 |
| Identity & secrets | `keycloak` | Keycloak | main 8180 |
| Identity & secrets | `vault` | Vault (persistent, auto-unsealed) | main 8200 |
| Observability | `jaeger` | Jaeger | ui 16686 · otlp_grpc 4317 · otlp_http 4318 |
| Observability | `monitoring` | Prometheus, Grafana | prometheus 9090 · grafana 3000 |
| Email | `mailpit` | Mailpit | main 1025 · ui 8025 |
| Workflows | `temporal` | Temporal, Temporal DB, Temporal UI | main 7233 · ui 8233 |

Nothing is installed by default. A fresh workspace is just the console.
Every entry is boot-tested with `scripts/test-catalog.sh`, which installs it,
waits for every service to be healthy, and uninstalls it again.

### Custom techs

Anything that runs as an image can be added without touching the catalog,
from the console (Catalog → Custom) or the terminal:

```bash
infrapack add mq --image nats:2-alpine --port 4222 --port 8222 --volume /data \
  --command "--jetstream --store_dir /data --http_port 8222" \
  --healthcheck "wget -qO- http://127.0.0.1:8222/healthz"
infrapack add shop --compose ./docker-compose.yml    # import an existing compose file
infrapack add … --dry-run                            # show what would be generated
```

Every host port and image tag becomes a setting, so custom techs are edited
like catalog ones. A compose import keeps services, ports, env, command,
healthcheck and depends_on; bind mounts become managed volumes; a service
named `*-ui` becomes the web UI card; `build:` is not supported. The
generated `~/.infrapack/stacks/<name>/compose.yml` is plain compose and safe
to edit by hand.

### Adding a tech to the catalog

Create `catalog/<name>/` with the files above. Look at `catalog/redis` for the
smallest example and `catalog/mysql` for hooks and commands. Start it with
`infrapack install <name>`; the console picks it up with no other change.

## Sharing a setup

### Per project: `infrapack.yaml`

Commit a small manifest to a repo and `infrapack up` inside it starts exactly
what that project needs, installing anything missing from the catalog first
(it asks; `-y` skips the question). `infrapack down` there releases that
project's techs and stops only the ones no other project is still using: if
project A brought up Kafka and MySQL and project B also uses Kafka, `down` in B
stops B's other techs and reports that Kafka is kept for A. Techs you started
yourself, by name or from the console, are held the same way and survive any
project's `down`. `infrapack status` lists who is using what. Naming a tech
explicitly (`infrapack down kafka`), or a global `infrapack down` outside any
project, always stops it.

```yaml
techs:
  - postgres
  - redis
settings:                  # optional, applied when a tech is first installed
  POSTGRES_DATABASE: shop
```

`infrapack init` writes one from whatever is running right now.

### Whole workspace: export / import

```bash
infrapack export team.json                 # every installed tech + settings
infrapack export team.json --with-secrets  # include passwords/tokens too
infrapack import team.json                 # on the new joiner's machine
infrapack import https://…/team.json       # or straight from a URL
```

Catalog techs travel by name and are re-installed from the catalog; custom
techs travel with their full definition. Settings come along, secrets masked
unless asked for. Techs already installed locally are skipped (`--force`
imports over them). The console's Docker page has the same Export / Import.

## Start-up behaviour

The console comes back whenever Docker starts (`CONSOLE_RESTART=unless-stopped`).
Installed techs do **not**; you turn them on when you need them. Set
`INFRA_RESTART=unless-stopped` in the console's settings if you would rather
have whatever was running come back after a reboot.

## Development

```bash
infrapack rebuild               # after editing anything under console/ or bin/
INFRAPACK_DEBUG=1 infrapack …   # show where an unexpected exit came from
scripts/test-catalog.sh redis   # boot-test one or more catalog entries
```

The console image (`ghcr.io/mostly-works-studio/infrapack:<version>`) bundles
the CLI and the catalog, so a released version pulls it and a checkout builds
it. `VERSION` is the single source of truth for both.

### Releasing

```bash
scripts/release.sh 0.2.0        # bumps VERSION and commits
git push
```

One workflow does the rest. Every push to `master` runs lint, the smoke test
and the full catalog boot; when all three are green and `VERSION` is not yet
tagged, the same run tags it, pushes the multi-arch console image to GHCR,
creates the GitHub release and updates the formula in
`Mostly-Works-Studio/homebrew-tap` (needs a `TAP_GITHUB_TOKEN` repository
secret with write access to the tap). A push whose version is already
released stops after CI. Pull requests run lint and smoke only.
