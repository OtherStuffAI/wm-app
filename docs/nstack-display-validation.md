# NStack display and identity validation

1. Add a reachable NStack with the unlocked native identity. Rename it to a
   friendly local name, select a backup workspace and save a browser link and
   preference. Restart the app; confirm the name and associations remain.
2. Refresh workspace discovery and confirm it preserves the local name.
3. Edit the address to an endpoint advertising the same complete Tower service
   npub. Confirm there is one saved NStack, the selected workspace remains and
   browser settings and backup selection persist. Endpoint metadata is refreshed.
4. Try an endpoint advertising another Tower identity or omitting identity.
   Confirm rejection leaves saved data unchanged. Add a separate connection if
   that identity is intentional. Legacy connections may need a successful refresh
   at the old endpoint before an identity-preserving move is possible.
5. Review cards, workspace rows, active identity introduction, service status,
   backup summaries, selector labels and routine failure messages. URLs,
   hostnames, full public keys and UUIDs should appear only after deliberate
   reveal/edit actions. Neutral legacy names and unavailable identities are
   expected when discovery has not supplied identity metadata.
6. Open connection details, copy the full identities and inspect/edit the URL.
   Close the details and confirm ordinary displays hide those values again.
   Give two NStacks the same name; their abbreviated public identities should
   distinguish them. Abbreviations must never be used for identity matching.

7. At 320, 375 and 390 logical pixels, repeat with text scaling at 1, 1.5
   and 2. Names and abbreviated identities must retain horizontal lines. Long
   names stop after two lines; identity stays on one line with ellipsis. Open
   the NStack actions menu and exercise rename, details, address editing and
   removal confirmation/cancellation. Refresh remains directly accessible.
   On desktop, inline actions remain available when the card has enough width;
   an embedded narrow card or larger text uses the same compact menu.
8. Select a backup workspace, including one with a long name. Scroll through
   the backup summary, open details, and check that copy controls, address help
   and removal buttons remain reachable. Locked identities disable refresh and
   address changes; busy operations disable secondary actions.

Automated checks: run Flutter analysis, then Flutter tests sequentially. The
identity edit tests reload a new preferences-backed store to simulate restart;
widget tests cover hidden default values, explicit reveal, rename persistence,
responsive geometry, menus, confirmations and busy/locked controls. The layout
matrix uses 320/375/390/1200 logical pixels and text scales 1/1.5/2. Optional
widget screenshots can be captured by setting `NSTACK_SCREENSHOTS` to a verified
ignored, untracked directory under `tmp/docs/handoffs/`, and
`NSTACK_FONT_DIRECTORY` to the Flutter SDK's `bin/cache/artifacts/material_fonts`
directory, then running `flutter test test/nstack_screen_test.dart --plain-name
'readable NStack'`. These are simulated Flutter renders rather than device
captures. They do not establish real remote discovery, device restart or
TestFlight availability.
