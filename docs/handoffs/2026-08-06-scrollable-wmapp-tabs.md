# Fix WM-App Flutter tab-strip scrolling on iPhone

Pete has confirmed the signed Release build opens successfully on his connected iPhone, but the requested WM-App tab navigation remains broken.

Observed physical-device behaviour:

- Flight Deck is the default tab, as intended.
- The horizontal WM-App tab strip cannot be scrolled/swiped far enough.
- The Autopilot tab opens partly off-screen and is difficult to select.

This is a Flutter WM-App host UI issue. Do not change or redeploy Flight Deck web assets.

Environment:

- Repo: `/Users/mini/code/wingmanbefree/wm-app`, default branch `main`.
- Physical device: Peter's iPhone, iPhone 15 Pro, UDID `00008130-001824141442001C`.
- Current signed standalone Release workflow was added in commit `3f59072`.
- Existing related Flight Deck task: `8d027899-b8be-4f8b-8b71-976875e7939b`.
- Origin thread: `cc772551-c396-409d-ba5c-42f5aae173a6`.

Required work:

- Inspect the Flutter tab bar implementation and reproduce at the physical iPhone viewport.
- Preserve Flight Deck as the default selected tab.
- Make the tab strip genuinely horizontally scrollable/swipeable on iPhone.
- Ensure the last tab, including Autopilot, can scroll fully into view with adequate trailing space and has a reliable tap target.
- Preserve tap selection, selected-tab visibility, desktop behaviour, and any tab reordering behaviour.
- Add focused widget coverage for constrained width, scrolling to the final tab, and selecting Autopilot.
- Run focused tests, full relevant Flutter tests, and `flutter analyze`.
- Build a signed Release, install it on the connected iPhone, launch it, and verify the strip and Autopilot tab physically if device state permits.
- Commit all nonignored tested state on `main`, preserving concurrent work. Do not push or deploy.

Report root cause, changed files, commit, validation, and physical-device evidence. Update/reopen the related Flight Deck task if broker capability is available; otherwise report the exact task-update gap to Rick.
