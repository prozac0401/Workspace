"""Prepare only the reviewed public JSON; local builds default to unavailable data."""
import os
from pathlib import Path
import subprocess


def on_pre_build(config, **kwargs):
    root = Path(__file__).resolve().parents[2]
    command = ['node', str(root / 'tools/calendar/prepare-site.mjs')]
    source = os.environ.get('CALENDAR_DATA_FILE')
    if source:
        command.extend(['--source', source])
    if os.environ.get('CALENDAR_PRODUCTION') == '1':
        command.append('--production')
    subprocess.run(command, cwd=root, check=True)
