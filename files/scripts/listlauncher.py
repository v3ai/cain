#!/usr/bin/env python3
"""Edit list.html on rhettapplestone.com in micro, then commit and push it."""

import os
import subprocess
from pathlib import Path

SITE = Path(os.environ.get("CAIN_SITE_DIR", Path.home() / "Desktop" / "rhettapplestone.com"))

subprocess.run([os.environ.get("EDITOR", "micro"), "list.html"], cwd=SITE)
subprocess.run(["git", "add", "."], cwd=SITE)
subprocess.run(["git", "commit", "-m", "qcom"], cwd=SITE)
subprocess.run(["git", "push"], cwd=SITE)
