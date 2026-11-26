# Fauna roadmap

## Now: grow the library to 365 animals

Written in the Claude Code session from each animal's Wikipedia article (no API cost), in
batches, using `scripts/plan/plan.json` (species chosen and checked by `scripts/plan/verify.py`).
Each batch: write `scripts/new_animals/batch_NN.json`, run `scripts/add_animals.py` and
`scripts/validate_content.py`, push. Phones pick new animals up via ContentSync.

## Then: release to everyone (remind the owner when 365 is reached)

1. Serve content through a free CDN (jsDelivr) from a stable branch, not the working branch.
2. Write and host a privacy policy (Fauna collects no personal data).
3. Prepare the App Store listing: description, keywords, Education category, age rating, screenshots.
4. Public TestFlight link (up to 10,000 people; Apple beta review, usually a day).
5. Submit to the App Store, after the owner approves.
