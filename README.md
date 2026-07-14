# reasonix-actions

GitHub Actions for running [Reasonix](https://reasonix.io) in CI/CD, focused on
**small footprint** and **multi-agent PR review**.

> This repository consumes a custom Reasonix binary from
> `sun-praise/deepseek-reasonix` that includes the `multi-review` command.

## Why Reasonix?

Reasonix is a tiny, statically-linked Go binary (~10 MB). These actions avoid
npm/Node entirely: they download the platform-native binary from a GitHub
Release, cache it, and run it directly. This keeps runner setup fast and the
workspace clean.

## Actions

### `setup-reasonix`

Installs and caches the Reasonix CLI.

```yaml
- uses: sun-praise/reasonix-actions/setup-reasonix@v1
  with:
    version: "1.17.12"
    install-source: "sun-praise/deepseek-reasonix"
```

### `reasonix-multi-review`

Runs parallel reviewer personas on a PR and posts a synthesized comment.

```yaml
- uses: sun-praise/reasonix-actions/reasonix-multi-review@v1
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    deepseek-api-key: ${{ secrets.DEEPSEEK_API_KEY }}
    model: "deepseek-flash"
    team: "quality,security,performance"
    language: "zh"
```

## Example workflow

```yaml
name: Reasonix Multi-Review

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4

      - uses: sun-praise/reasonix-actions/reasonix-multi-review@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          deepseek-api-key: ${{ secrets.DEEPSEEK_API_KEY }}
          model: deepseek-flash
          team: "quality,security,performance,architecture"
          language: zh
          timeout-seconds: "900"
```

## Personas

The `multi-review` command ships with these built-in personas:

- `quality` — correctness, maintainability, tests
- `security` — auth, injection, secrets, crypto
- `performance` — allocations, I/O, hot paths
- `architecture` — layering, coupling, API surface

## Development

- `setup-reasonix/install-reasonix.sh` is POSIX/Bash and should pass `bash -n`.
- Action metadata lives in `setup-reasonix/action.yml` and
  `reasonix-multi-review/action.yml`.

## License

Apache 2.0
