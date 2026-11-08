Bats rules adapted from bats-core/bats-vscode, `syntaxes/bats.extended.tmLanguage`
(master, retrieved 2026-11-08), MIT; see LICENSE.bats-vscode. The wrapper's
`source.shell` include is replaced by the vendored shell grammar. Injection rules
are prepended to initial_context and normal_context so Orca needs no injections.

Shell grammar vendored from microsoft/vscode,
`extensions/shellscript/syntaxes/shell-unix-bash.tmLanguage.json` (main, retrieved
2026-11-08), generated from jeff-hykin/better-shell-syntax commit
35020b0bd79a90d3b262b4c13a8bb0b33adc1f45, MIT; see
LICENSE.better-shell-syntax. The scope is renamed to source.shell.bats. Two dangling
upstream includes are supplied locally: line_continuation_character (escaped
newline) and arithmetic_dollar ($((…)) with existing math/string rules).
All includes resolve inside this grammar; no external scopes are required.
