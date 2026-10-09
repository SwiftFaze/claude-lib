# Intent docs

One `<feature-slug>.md` file per feature, written by a human (or derived from a GitHub issue via the `spec-intent`
skill) before implementation starts. This is the source of *why* a feature exists and what it must do.

See `.claude/workflow.md` for the high-risk vs. standard path split: on the high-risk path (the high-risk triggers in
its project configuration), `specs/features/<feature-slug>.feature` is generated from this doc and reviewed/approved
before any code is written. On the standard path, this doc still gets written first, but feeds directly into an agile
implementation loop instead — no fully-approved `.feature` file is required before code exists.

Intent is not written once and frozen: clarifying answers gathered while drafting or implementing get appended back
here.

Copy `TEMPLATE.md` to `<feature-slug>.md` to start a new one.

These docs are local scratch, not version-controlled: add this to the project's `.gitignore` so only `README.md` and
`TEMPLATE.md` are committed:

```
specs/intent/*
!specs/intent/README.md
!specs/intent/TEMPLATE.md
```

Unlike `specs/features/*.feature` — which stays a real, executable check through the acceptance runner — an intent doc
has no equivalent once a feature is built: the code itself, and its `.feature` file where one exists, are what
actually persist.
