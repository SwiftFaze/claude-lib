# Feature specs (Gherkin)

One `<feature-slug>.feature` file per **distinct concept**, generated from
the matching file in `specs/intent/`. Do not hand-edit a `.feature` file
ahead of its intent doc — update the intent doc first, then regenerate.

**One feature file, one thing.** If an intent doc covers multiple
unrelated concepts (e.g. a new login method *and* a new export format),
don't bundle them into one combined file like
`added-login-and-export.feature` — split into `login-sso.feature` and
`export-csv.feature`, each named for the specific thing it covers. A single
intent doc can produce more than one `.feature` file when it isn't actually
a single cohesive concept.


## Finding what's covered where

Concept-based naming (above) means related behavior is spread across
several files instead of one per class. Every `.feature` file carries
its own description block under `Feature:` saying what it covers, what it
supersedes, and what's explicitly out of scope — that block is the single
source of truth, kept next to the scenarios it describes.

To browse all of them at once:

```
grep -A5 '^Feature:' specs/features/*.feature
```

To find which file covers a concept, grep for the concept directly — it
searches the description blocks and the scenarios together.
