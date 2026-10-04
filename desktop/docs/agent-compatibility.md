# Which agents the desktop app works with

Measured 2026-10-04 by building each release from its tag and running the whole desktop test suite
(`cargo test --locked`, `RFE_AGENT_BIN` pointing at that build) against it.

| Agent release | Sign in with an account | Pair with a code | Approve on the PC | Result |
|---|---|---|---|---|
| `agent-v1.42.6` | yes | yes | no, endpoint missing | all tests pass; the 7 approval tests skip |
| `agent-v1.42.7` (last stable) | yes | yes | no, endpoint missing | all tests pass; the 7 approval tests skip |
| `agent-v1.43.0-rc.1` | yes | yes | yes | all tests pass |
| built from the checkout | yes | yes | yes | all tests pass (the main CI job) |

**Minimum agent:** `agent-v1.42.6`, the oldest release tag that exists, for everything except approving
on the PC. Approval needs **`agent-v1.43.0-rc.1`** or newer (`POST /pair/request`, added in commit
`17a887ad`). Releases older than 1.42.6 were not tried.

What the app does with an agent that is too old for approval: the agent answers the endpoint with a bare
`404 page not found`, and the app says "This agent is too old to approve a new computer from the PC (it
needs agent-v1.43.0-rc.1 or newer). Pair with a code or sign in with an account instead." instead of
showing `HTTP_404`.

## How CI keeps this true

`desktop.yml` runs the suite twice: against an agent built from the same checkout (a missing feature
fails), and against the newest stable `agent-v*` tag, which is not a `-rc` (the tests of features that
release lacks may skip, because that job sets `RFE_ALLOW_OLD_AGENT=1`). When the stable release catches up
with the checkout, the second run simply tests the same thing. Neither run has happened on GitHub yet.

Pick the agent tag to test by hand with `RFE_AGENT_BIN`, building it from `git archive <tag> agent`.
