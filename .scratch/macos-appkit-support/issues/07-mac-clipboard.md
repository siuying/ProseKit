# macOS clipboard: cut/copy/paste via a Pasteboard protocol

Status: ready-for-agent

Context: Q7 (Pasteboard protocol + edit-action validation).

## What to build

Cut/copy/paste on macOS. Abstract the pasteboard behind a small `Pasteboard`
protocol (`hasStrings`, `string` get/set) that both `UIPasteboard` and
`NSPasteboard` satisfy, replacing the iOS-only `UIPasteboard` dependency and
keeping the test-injectability that already exists. The copy/cut/paste actions
arrive through the AppKit responder chain (`copy:`/`cut:`/`paste:`); gating goes
through `validateUserInterfaceItem(_:)`/`validateMenuItem(_:)`, routed to the
same core "can perform" query iOS's `canPerformAction` uses.

Clipboard payload stays plain-string for now (matching iOS); rich **Slice**
fidelity is out of scope.

## Acceptance criteria

- [ ] `Pasteboard` protocol with `UIPasteboard` and `NSPasteboard` conformances;
      the editor depends on the protocol, not a concrete type.
- [ ] Copy/cut/paste work in the Mac editor over a selection.
- [ ] Copy/cut are disabled with no selection; paste is disabled with an empty
      pasteboard — gated through the shared core "can perform" query.
- [ ] Both the contextual menu and (later) the Edit menu validate through the
      same query.
- [ ] macOS UI test: copy a selection and paste it elsewhere; cut removes the
      selection — asserted against the rendered document.

## Blocked by

- 05-mac-mouse-selection
