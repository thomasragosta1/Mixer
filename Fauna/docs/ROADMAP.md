# Fauna roadmap

## Done: the library has 365 animals

365 animals across all seven groups and every region, worldwide. Written in the Claude Code session from each animal's Wikipedia article (no API cost), in
batches, using `scripts/plan/plan.json` (species chosen and checked by `scripts/plan/verify.py`).
Each batch: write `scripts/new_animals/batch_NN.json`, run `scripts/add_animals.py BATCH.json` and
`scripts/validate_content.py`, push. Phones pick new animals up via ContentSync.

## Next: release to everyone

1. Serve content through a free CDN (jsDelivr) from a stable branch, not the working branch.
2. Write and host a privacy policy (Fauna collects no personal data).
3. Prepare the App Store listing: description, keywords, Education category, age rating, screenshots.
4. Public TestFlight link (up to 10,000 people; Apple beta review, usually a day).
5. Submit to the App Store, after the owner approves.
