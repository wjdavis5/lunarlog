# Residual review findings: fix/gate-system-ui-relock

Source: `ce-code-review` run `20260903-162145` on branch
`fix/gate-system-ui-relock` (head `bd43f3e` at review time), plan
[`docs/plans/2026-09-03-003-fix-gate-discards-granted-unlock-plan.md`](../plans/2026-09-03-003-fix-gate-discards-granted-unlock-plan.md).
Seven reviewers: correctness, security, adversarial, reliability, testing,
project-standards, maintainability.

Everything P0/P1 was applied in `f9bd5d3` — the fail-closed answer to an
absorbed departure, the stale-grant generation guard, the deadline
releasing `_authenticating`, the inactivity countdown suspended for a
window, the disposal guard, the un-gated cover fix, and the user-facing
copy that had promised a bound the code did not enforce. The items below
were judged real but narrower, and are tracked rather than applied.

A follow-up review after `c412de1` resolved the original review's stale-close
and window-reopen items with per-window epochs. It also kept the absolute
deadline armed through settlement, made every completed action absorb trailing
lifecycle events, covered content while app-launched system UI is active, and
guarded the last post-disposal notification.

## Residual findings

- **P2 — after a deadline lock during `_addMethod`, the remainder of that
  ceremony runs unprotected.** The counter is zeroed, so the subsequent
  `link()` picker opens with no window and its own `inactive` re-locks. The
  operator is already behind the lock screen at that point, so this is
  incoherent rather than exposing.
- **P2 — one pre-existing re-auth test cannot fail on its lock assertion.**
  `test/ui/gate_test.dart`'s "returns false when the prompt is interrupted"
  case uses `FakeGate(requiresUnlock: false)`, so `lock()` can never set
  `_locked` and `expect(controller.locked, isFalse)` holds regardless. Its
  return-value assertion is meaningful; the lock one is not. Untouched by
  this branch by design (KTD7/KTD8 keep existing assertions frozen), so it
  is filed rather than edited.

## Deliberate deviations from the plan

- **KTD2a's "close the window early on `resumed`" is not implemented.** The
  settling tail always runs its full duration. Ending it on `resumed` would
  re-expose a trailing `inactive` that arrives *after* the resume, which is
  the ordering the tail exists to absorb. Cost: a genuine departure inside
  the ~3s tail is answered at the tail's end rather than immediately — and
  it *is* answered, fail-closed, since `f9bd5d3`.
- **`systemUiDeadline` defaults to the same two minutes as
  `inactivityTimeout`.** In production the two are indistinguishable by
  observation, so a regression silently disabling the window deadline would
  be masked by the inactivity timer everywhere except the tests that inject
  a distinct duration (they do). The plan's Open Questions already carries
  the "should the window bound be shorter" question.

## Not run

- **`dart run tool/mutation_gate.dart`** — the plan's Verification Contract
  asks for it on U1's logic. It was started and abandoned: for files with
  no 1:1 test mirror (`lib/app_lifecycle.dart` among them) the tool runs the
  entire 563-test suite per mutant, which is hours, and it rewrites `lib/`
  in place while doing so — it twice reverted uncommitted work and left a
  live mutant in the tree before being killed. Run it deliberately, in the
  foreground, on a committed tree with nothing else in flight.
- **The device checklist** in [`docs/ops/supabase-go-live.md`](../ops/supabase-go-live.md).
  No macOS or physical device in this session. The gate's real behaviour on
  a real authenticator is unproven by `flutter test` by construction — the
  suite always drives a fake — which is exactly how issue #65 shipped. The
  checklist's bounded-suppression item (both halves) is the one that would
  have caught the P0 fixed here.
- **The cross-model adversarial peer pass.** Available (`grok` is
  installed) but not run: it would send this repo's diff to a third party,
  and this review was agent-initiated rather than user-requested. The
  in-process adversarial reviewer ran instead.
