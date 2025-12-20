# Alkon Code Patterns

- Prefer small, testable steps; add commands incrementally (e.g., init → list → fzf).
- Always parse args early (`parse_args`) and dispatch in `main`.
- Use shared `boilerplate.sh` for `info/warn/fail` messages.
- Default to local config (`Alkon.toml` in repo); allow `--config=` override and per-run overrides (e.g., `--tool-chest=`).
- Detect environment before acting: check `gh auth status`, presence of `fzf`, config file existence; fail fast with actionable messages.
- Prompt with defaults when deriving values (e.g., owner from `gh` or git config; tool chest default).
- Avoid destructive actions by default; confirm before cloning or launching external commands.
- Keep logs/debug lines minimal but add temporary debug when chasing errors; remove once stable.
