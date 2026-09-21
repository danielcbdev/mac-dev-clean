# Docker output fixtures

Synthetic output in the documented schemas, written by hand. Sanitized captured
output from a real daemon can replace these later without changing any test:
the parsers are what the tests exercise, not the daemon.

`--format {{json .}}` and `buildx du --format=json` both emit **newline-delimited
JSON objects**, not a JSON array, so these `.json` files hold one object per
line. `inspect` output really is an array, and those fixtures are arrays.

Nothing here contains a real project name, image, path or account.
