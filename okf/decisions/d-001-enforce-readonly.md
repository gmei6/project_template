---
type: Decision
mutability: append-only
timestamp: 2026-07-03T21:31:16-04:00
---
# Decision: Enforce read-only status via Python scripts

We decided to replace manual agent edits of append-only OKF files with Python scripts (`append_okf.py` and `get_context.py`). 
We also enforce read-only status on append-only files using `chmod 444`. 
This is for token efficiency and strict safety to enforce immutability.
