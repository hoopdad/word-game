# Mike TODO (Remaining questions)

1. For category-agent output, should the canonical schema use:
   - a single object keyed by category (`{"category": ["phrase1", "phrase2"]}`), or
   - an array of category objects (`[{"category":"x","phrases":[...]}]`)?

2. The requirement says "round timer resets on start of a new category and does not reset during a round." Confirm that "new category" always means "new round" so there is exactly one timer window per round.

3. For WAF errors, should user-facing responses be standardized to a specific status/body contract (for example, fixed 403 payload and tracking ID)?
