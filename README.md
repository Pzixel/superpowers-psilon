# Superpowers psilon

Eight personal forks of [obra/superpowers](https://github.com/obra/superpowers), adapted for Codex 5.6, plus one repository-authored ClickHouse table-design guard. They use narrow implicit triggers, exact-target evidence gates, proportional workflows, and repository-owned policy.

The original Superpowers plugin is not required.

## Skills

| Skill | Trigger |
|---|---|
| `superpowers-brainstorming-psilon` | Consequential design uncertainty or coupled-system decomposition |
| `superpowers-writing-plans-psilon` | Durable multi-stage, coordinated, risky, or cross-session plans |
| `superpowers-subagent-driven-development-psilon` | Large accepted plans with disjoint scopes and verified prerequisites |
| `superpowers-dispatching-parallel-agents-psilon` | Two or more proved-independent substantial workstreams |
| `superpowers-systematic-debugging-psilon` | Observed failures with uncertain root cause |
| `superpowers-requesting-code-review-psilon` | Independent review at a material integration-risk boundary |
| `superpowers-receiving-code-review-psilon` | Concrete review feedback to assess or implement |
| `superpowers-verification-before-completion-psilon` | Fresh proof before production, security, data, concurrency, migration, contract, release, or broad-system completion |
| `superpowers-clickhouse-table-design-psilon` | Any proposed or actual ClickHouse table creation or schema change |

## Install for one user

Clone the repository, then link each skill into Codex's user scope:

```bash
git clone https://github.com/Pzixel/superpowers-psilon.git
cd superpowers-psilon

for skill in superpowers-*-psilon; do
  ln -s "$PWD/$skill" "$HOME/.agents/skills/$skill"
done
```

Codex follows skill-directory symlinks. A later `git pull` updates every linked skill. If Codex does not show an update, restart it.

## Validate changes

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python scripts/validate-skills.py

scripts=(
  superpowers-brainstorming-psilon/scripts/*.sh
  superpowers-subagent-driven-development-psilon/scripts/*
  superpowers-systematic-debugging-psilon/*.sh
)
for script in "${scripts[@]}"; do
  bash -n "$script"
done

git diff --check
```

GitHub Actions runs the same structural and shell checks and scans the full Git history for secrets.

## Maintenance rules

- Keep activation descriptions specific, with positive and negative boundaries; maximum 60 words and 450 characters.
- Keep each `SKILL.md` at or below 250 lines and 2,500 words.
- Put optional examples, prompts, and detailed techniques in one-level companion files.
- Preserve strong gates and exceptions while removing duplicate prose.
- Record upstream lineage and every behavior change in [ORIGINS.md](ORIGINS.md).
- Never commit credentials, tokens, private keys, environment files, or local app artifacts.

## Provenance and license

[ORIGINS.md](ORIGINS.md) pins the upstream release and explains each adaptation. Upstream-derived material remains under the MIT license in [LICENSE.superpowers](LICENSE.superpowers).
