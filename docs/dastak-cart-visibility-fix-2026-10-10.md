# Customer cart ownership: background-tab correction

The previous recovery release (5636e73) still acquired the editing Web Lock for
the full mounted Customer root, including Orders/Profile/Settings and hidden
tabs. A timeout message also asserted another cart was open without checking it.

This correction releases ownership and cancels pending acquisition when the
document becomes hidden. Hidden mounts cannot acquire editing. Returning to a
visible page cooperatively requests editing and rereads the saved cart before
enabling writes. The waiting message no longer claims a confirmed second cart.
The native exclusive lock, strict storage checks, and checkout guards remain.

Verification: 148 test files / 1,056 tests passed, production TypeScript/Vite
build passed, targeted ESLint and git diff checks passed. New tests cover hidden
release, blocked hidden writes, latest-cart restoration, and hidden startup.

Safari inspection found another Customer document on a delivered-order screen,
but its lock ownership and release version were not confirmed. Web Inspector
remained blank, then native access timed out after the Mac locked/unlocked.
Do not claim the user's live cart is verified fixed from these tests alone.
An already-open page running an older release must load the new code; deployment
does not replace JavaScript in open documents. No live cart/order edits occurred.
