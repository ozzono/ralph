# Custom Ralph

This is a custom fork of [Ralph](https://ghuntley.com/ralph/) configured to run as container-based autonomous AI agent loops. It provides Docker containers pre-loaded with Claude Code, Go, and optionally Flutter, so you can mount any project and let Ralph iterate on it inside an isolated environment.

![Ralph](ralph.webp)

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/). [Read Ryan Carson's in-depth article on how he uses Ralph](https://x.com/ryancarson/status/2008548371712135632).

## How It Works

Ralph is an autonomous AI agent loop that runs Claude Code repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context. Memory persists via git history, `progress.txt`, and `prd.json`.

1. You define user stories in `prd.json`
2. Ralph spawns a fresh Claude Code instance each iteration
3. The agent picks the highest-priority incomplete story, implements it, runs quality checks, and commits
4. Repeats until all stories pass or max iterations are reached

## Container Variants

### `ralph-loop` (Dockerfile)

General-purpose container with:
- Ubuntu 24.04, Node.js 22, Go 1.23.6
- Claude Code CLI
- zsh + Oh My Zsh
- Git security wrapper (restricts git access to interactive shells only)

### `ralph-flutter` (Dockerfile.flutter)

Everything in `ralph-loop` plus:
- Flutter 3.27.4 SDK (web + linux precached)
- Flutter build dependencies (clang, cmake, ninja-build, GTK3, etc.)

## Makefile

| Rule | Command | Description |
|------|---------|-------------|
| `make build` | `docker build -f Dockerfile -t ralph-loop:latest .` | Build the general-purpose container |
| `make build-flutter` | `docker build -f Dockerfile.flutter -t ralph-flutter:latest .` | Build the Flutter container |

## Shell Aliases

Add these to your `.zshrc` or `.bashrc` to quickly launch Ralph containers for any project:

### `ralph-loop`

Starts (or attaches to) a `ralph-loop` container with the current directory mounted at `/workspace/application`. Copies your Claude credentials into the container automatically.

```sh
ralph-loop() {
  local name="$(basename "$(pwd)")"

  if ! docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
    docker run -d --rm \
      -v "$(pwd):/workspace/application" \
      -w /workspace \
      --user "ralph:ralph" \
      --name "$name" \
      ralph-loop

    [ -f "$HOME/.claude/.claude.json" ] && docker cp "$HOME/.claude.json" "$name":/home/ralph/.claude.json 2>/dev/null || true
    [ -f "$HOME/.claude/settings.json" ] && docker cp "$HOME/.claude/settings.json" "$name":/home/ralph/.claude/settings.json 2>/dev/null || echo "$HOME/.claude/settings.json not found"
    [ -f "$HOME/.claude/.credentials.json" ] && docker cp "$HOME/.claude/.credentials.json" "$name":/home/ralph/.claude/.credentials.json 2>/dev/null || echo "$HOME/.claude/.credentials.json not found"
  fi

  docker exec -it -u ralph "$name" zsh
}
```

### `ralph-flutter`

Same as above but uses the `ralph-flutter` image. Container name is suffixed with `-flutter`.

```sh
ralph-flutter() {
  local name="$(basename "$(pwd)")"
  local container_name="${name}-flutter"

  if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    docker run -d --rm \
      -v "$(pwd):/workspace/application" \
      -w /workspace \
      --user ralph:ralph \
      --name "$container_name" \
      ralph-flutter

    [ -f "$HOME/.claude/.claude.json" ] && docker cp "$HOME/.claude.json" "$container_name":/home/ralph/.claude.json 2>/dev/null || true
    [ -f "$HOME/.claude/settings.json" ] && docker cp "$HOME/.claude/settings.json" "$container_name":/home/ralph/.claude/settings.json 2>/dev/null || true
    [ -f "$HOME/.claude/.credentials.json" ] && docker cp "$HOME/.claude/.credentials.json" "$container_name":/home/ralph/.claude/.credentials.json 2>/dev/null || true
  fi

  docker exec -it -u ralph "$container_name" zsh
}
```

## Usage

### Quick Start

```bash
# 1. Build the container
make build            # or: make build-flutter

# 2. cd into your project and launch
cd ~/my-project
ralph-loop            # or: ralph-flutter

# 3. Inside the container, run ralph
./ralph.sh --tool claude 10
```

### Running Ralph

```bash
# Using Amp (default)
./ralph.sh [max_iterations]

# Using Claude Code
./ralph.sh --tool claude [max_iterations]
```

Default is 10 iterations. Ralph will:
1. Create a feature branch (from PRD `branchName`)
2. Pick the highest priority story where `passes: false`
3. Implement that single story
4. Run quality checks (typecheck, tests)
5. Commit if checks pass
6. Update `prd.json` to mark story as `passes: true`
7. Append learnings to `progress.txt`
8. Repeat until all stories pass or max iterations reached

### Workflow

1. **Create a PRD** - Use the `/prd` skill to generate a requirements document
2. **Convert to Ralph format** - Use the `/ralph` skill to convert the PRD to `prd.json`
3. **Run Ralph** - `./ralph.sh --tool claude`

## Key Files

| File | Purpose |
|------|---------|
| `Dockerfile` | General-purpose container (Node.js, Go, Claude Code) |
| `Dockerfile.flutter` | Flutter variant with SDK + build deps |
| `Makefile` | Build rules for both container images |
| `ralph.sh` | Bash loop that spawns fresh AI instances per iteration |
| `prompt.md` | Prompt template for Amp |
| `CLAUDE.md` | Prompt template for Claude Code |
| `prd.json` | User stories with `passes` status (the task list) |
| `prd.json.example` | Example PRD format for reference |
| `progress.txt` | Append-only learnings across iterations |
| `skills/prd/` | Skill for generating PRDs |
| `skills/ralph/` | Skill for converting PRDs to JSON |
| `flowchart/` | Interactive visualization of the Ralph loop |

## Git Security Model

Inside the container, git is wrapped so that only interactive zsh sessions can use it. When Claude Code spawns subprocesses, `RALPH_GIT_ALLOWED` is unset via `.zshenv`, preventing the AI agent from running arbitrary git commands. This ensures commits only happen through the controlled `ralph.sh` flow.

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new AI instance** with clean context. The only memory between iterations is:
- Git history (commits from previous iterations)
- `progress.txt` (learnings and context)
- `prd.json` (which stories are done)

### Small Tasks

Each PRD item should be small enough to complete in one context window. Right-sized examples:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic

Too big (split these): "Build the entire dashboard", "Add authentication", "Refactor the API"

### Archiving

Ralph automatically archives previous runs when you start a new feature (different `branchName`). Archives are saved to `archive/YYYY-MM-DD-feature-name/`.

## Debugging

```bash
# See which stories are done
cat prd.json | jq '.userStories[] | {id, title, passes}'

# See learnings from previous iterations
cat progress.txt

# Check git history
git log --oneline -10
```

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Amp documentation](https://ampcode.com/manual)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
