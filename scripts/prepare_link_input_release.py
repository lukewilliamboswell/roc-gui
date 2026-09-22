#!/usr/bin/env python3
"""Compose a unified release from freshly tested component candidates."""

import argparse
from pathlib import Path

from link_input_artifacts import compose

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--components", type=Path, required=True)
    parser.add_argument("--resource", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    compose(args.components.resolve(), args.output.resolve(), args.resource.resolve())
