# Put Flight Deck inside the single scrollable WM-App tab strip

Pete clarified the intended tab semantics after testing commit `aed2923` on his iPhone.

Current incorrect behaviour:

- Flight Deck is visually fixed/pinned outside the horizontal scroll area.
- Only the tabs after Flight Deck scroll.

Required behaviour:

- There is one horizontal scroll strip containing Flight Deck and every other tab.
- Flight Deck remains the first tab in ordering and cannot be closed or reordered away from index zero.
- “Pinned” means first/fixed ordering only; it does not mean fixed to the viewport.
- Swiping left must move the whole strip, including Flight Deck, off-screen so later tabs such as Autopilot can become fully visible.
- Selecting any tab should reveal that tab without changing Flight Deck's first-position invariant.
- Preserve comfortable iPhone tap targets, long-press reordering for reorderable tabs, desktop behaviour, and Flight Deck as the initial/default selected tab.

Repo: `/Users/mini/code/wingmanbefree/wm-app` on `main`.
Physical iPhone UDID: `00008130-001824141442001C`.
Related Flight Deck task: `8d027899-b8be-4f8b-8b71-976875e7939b`.

Add/update constrained-width widget coverage proving Flight Deck itself scrolls off-screen, Autopilot becomes fully visible/selectable, and Flight Deck stays index zero after user-tab reordering. Run focused tests, full Flutter tests, and `flutter analyze`. Build a signed Release, install and launch it on the connected iPhone, and confirm the process remains live. Commit all nonignored tested state on `main`; preserve concurrent work; do not push or deploy.

## Implementation handoff

Root cause: Flight Deck was rendered as a fixed sibling before the horizontal
`ReorderableListView`, so the list's scroll offset applied only to user tabs.

Resolution:

- Flight Deck and user tabs now render in one horizontal reorderable list.
- Flight Deck has no close action or drag listener, and reorder destinations are
  clamped to index one or later.
- All tabs use a minimum 96-point width at constrained iPhone sizes.
- Selecting any tab asks the shared strip to reveal it, including selecting
  Flight Deck after it has scrolled away.
- The constrained-width widget test covers Flight Deck leaving the viewport,
  Autopilot becoming fully visible/selectable, and Flight Deck remaining at
  stack/list index zero after a user-tab reorder.

Validation completed:

- Focused widget test: passed.
- Full `flutter test`: 31 tests passed.
- `flutter analyze`: no issues found.
- Signed Release build: succeeded with team `N5DRUM6S94`.
- Physical iPhone install: succeeded on `00008130-001824141442001C`.

Device launch verification is pending only because iOS reported that the
connected phone was locked. Unlock the phone and retry `devicectl` launch, then
confirm `Runner` remains present in the device process list.
