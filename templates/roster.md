# Roster

| Unit | State | Depends on |
|---|---|---|
| `example` | unbuilt | — |

<!--
    The roster is the backlog. There is no ledger, no queue, no issue tracker mirror: the `unbuilt`
    rows ARE the work, and re-reading them is what grooms it.

    Order matters -- roughly, foundations first. The build command takes the earliest unit whose
    dependencies are all built.

    Cap this from its own size plus a small margin, in `roster.path`/`roster.cap`. The cap is what
    bounds how many units there are, which is the job it can only do while it pinches.
-->
