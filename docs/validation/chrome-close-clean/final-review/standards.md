# Standards review — 734d7d7 against 91c4cf5

Reviewed `git diff 91c4cf5...734d7d7`, repository AGENTS, documentation authority/validation instructions, ChromeProbe README, and the Fowler heuristic baseline. No documented-standard violation or production/personal-file authority expansion found. The workflow is manual/hosted-only, standard-root mapping refuses pre-existing roots and never deletes them, and mutation remains inside disposable canonical roots. Production Swift/UI and personal-file execution are unchanged.

Two nonblocking maintainability findings:

1. **Native-fault evidence is lost on failure** (`Validation/ChromeProbe/native-faults.py:76`). The sole JSON write follows every assertion. A denied-access/reopen/helper failure discards already completed index/access results and observed outcome objects; artifact upload receives only the provisioning/other-lane evidence. Save the accumulated report after each scenario and in an outer failure/finally path, including the failing scenario and actual exception. This is an evidence-durability recommendation, not a demand for more test scope or stronger safety guarantees.

2. **Possible Mysterious Name/readability smell** (`Validation/ChromeProbe/headed.mjs:30–46`). The CDP lifecycle and UI helpers compress multiple statements into single lines (`p.j`, `p.r`, `t`, `s`), including timeout and process teardown logic that reviewers must audit. Expand these helpers into ordinary multiline functions and descriptive resolver/timeout names. Keep them local; no generic browser framework or broad refactor is warranted for this bounded qualification script.

The header’s “No password DB, preference or Keychain changes” should also say “No direct … manipulation”: normal Chrome UI saving intentionally changes browser-managed state. This is a wording correction, not an extra qualification gate.

Assessment: two nonblocking recommendations; no blocking standards findings. Native pass/failure and supported-layout conclusions must come from source-bound hosted evidence, not this static review.
