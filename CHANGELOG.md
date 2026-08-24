## [1.25.2] - 2026-08-23
- docs: the 1.25.1 heading carried a literal `$(date +%Y-%m-%d)` instead of a date. It was written through a quoted heredoc (`<< 'CL'`), which suppresses command substitution. Corrected to 2026-08-22, the actual release date. The same defect was fixed in `theta-suite` (3.21.16, 3.21.17) and `theta-directory` (2.24.15).

## [1.25.1] - 2026-08-22
- Added docs/KNOWN_ISSUES.md for multi-site known limits and tradeoffs.
