# Contributing

## Branch and PR workflow

- Do not commit directly to `master`.
- Create a feature branch for every change.
- Open a pull request to `master`.
- Keep PRs focused and include a short test/verification note.

## Local checks

Run before opening a PR:

```bash
shellcheck install.sh uninstall.sh templates/*.sh
./tests/smoke.sh
```

## Notes

- This project is macOS-specific and uses `launchd`.
- Keep privileged behavior changes clearly documented in `README.md`.
