#!/usr/bin/env python3
"""Publish tested complete Windows stubs under an independent content-addressed release."""

from release_windows_inputs import main, prepare as _prepare

KIND = 'windows-system-imports'


def prepare(directory, tag, environment):
    return _prepare(directory, tag, environment, KIND)


if __name__ == '__main__':
    main(KIND, __doc__)
