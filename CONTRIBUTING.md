# Contributing to InfraPack

The most useful contribution is a catalog entry. If you set up a tech as a
custom entry and think other people would want it too, turn it into a catalog
entry and open a pull request. Every entry is boot-tested in CI, so a green
run is most of the review.

## Adding a tech to the catalog

A catalog entry is a directory under `catalog/<name>/`:

| file            | required | purpose |
|-----------------|----------|---------|
| `compose.yml`   | yes | the compose fragment: services, volumes, healthchecks |
| `stack.json`    | yes | label, blurb, category, and what the console shows: facts, links, settings |
| `defaults.env`  | yes | every `${VAR:-default}` used in compose.yml, with its default |
| `commands.sh`   | no  | `infrapack <name> <command>` helpers (a shell, a CLI, a sample) |
| `hooks/*.sh`    | no  | `pre-up`, `post-up`, `post-settings`, `post-install`, `pre-uninstall` |
| `files/…`       | no  | config files to bind-mount (referenced as `${INFRAPACK_HOME}/stacks/<name>/files/…`) |

Start from the closest existing entry: `catalog/redis` is the smallest,
`catalog/mysql` shows hooks and commands, `catalog/monitoring` a multi-service
stack, `catalog/vault` a sidecar, `catalog/maestro` a build-from-source image.

### The rules an entry has to follow

1. **Names.** Directory, `"stack"` in stack.json and the core service are the
   same lowercase name. A web UI service is `<name>-ui` (so `--no-ui` can skip
   it); other companions are `<name>-<role>`. Containers are
   `infrapack-<service>`; volumes start with `<name>-`.
2. **Every knob is a setting.** Host ports, image tags and credentials come
   from `.env` through `${VAR:-default}`, and every such VAR is listed in
   `defaults.env` and declared in `stack.json` `settings` so the console can
   edit it. Keys are `<NAME>_PORT`, `<NAME>_VERSION`, `<NAME>_UI_PORT`, and
   any other `<NAME>_*`.
3. **Unique default ports.** Pick host ports that clash with nothing else in
   the catalog (CI checks). If the tech's own port is taken by a sibling, use a
   nearby one and say so in a comment in `defaults.env` (Redpanda uses 19092
   because Kafka has 9092).
4. **A healthcheck**, unless the image has no shell at all. Use
   `127.0.0.1`, not `localhost`, in wget/curl checks (IPv6 bites otherwise).
   Give slow starters a generous `start_period`.
5. **Zero-login by default** where the software allows it, and dev
   credentials otherwise, shown as facts. Never require the user to read logs
   to get in.
6. **Data persists** in a named volume unless the tech is an emulator that is
   in-memory by design; say so in the blurb if it is.
7. **Pin the image tag** to a major or minor version, not `latest`, when the
   tag scheme allows it. CI re-boots the catalog weekly and will tell us when
   a pinned tag disappears.
8. **In-network facts.** Besides `localhost:<port>`, show how another
   container reaches it (`<service>:<container port>`).
9. **Platforms.** If the image exists for one CPU architecture only, add
   `"platform": "linux/amd64"` to stack.json; InfraPack then checks emulation
   before installing.

### Test it

```bash
infrapack install <name>          # from your checkout, with bin/ on PATH
infrapack status; infrapack urls   # facts render, links open, settings edit
scripts/test-catalog.sh <name>    # what CI runs: install, wait for healthy, uninstall --purge
```

Then `infrapack rebuild` and check the card in the console (the image bundles
the catalog).

### From a custom tech

If you already run it as a custom tech, `infrapack contribute <name>` writes a
catalog-shaped copy of it into `./infrapack-catalog/<name>/` with the custom
marker removed and a checklist of what to polish (blurb, category, facts,
healthcheck, pinned tag). Move that directory into `catalog/` in your fork.

### Open the PR

- One entry per PR, titled `catalog: <name>`.
- Say what it is in one line and why people would want it locally.
- CI runs lint and the smoke test on the PR; a maintainer runs the boot test
  for the new entry before merging, and the full catalog boots on `master`.

## Other contributions

- **CLI and console**: keep the host requirement at bash + Docker. Anything
  that needs Python runs inside the console image. Bash must stay 3.2
  compatible (macOS ships that): no associative arrays, no `mapfile`.
- **Tests**: the CI smoke job in `.github/workflows/ci.yml` is the end-to-end
  check; extend it when adding a command.
- **Releases** are cut by maintainers with `scripts/release.sh`.

## Categories

`database`, `cache`, `messaging`, `search`, `storage`, `cloud`, `auth`,
`observability`, `mail`, `workflow`. If none fits, use the nearest and say so
in the PR; a new category is a one-line change in the console.
