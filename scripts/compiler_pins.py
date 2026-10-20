# Vendored from roc-automation e1c09714c4d9e93fc03d2d1e4186ca543bc60d50.
# License: UPL-1.0; see vendor/roc-automation-LICENSE.
"""Narrow reader that finds a compiler pin in a Roc root header.

This is not a Roc parser: the consumer compiler remains the grammar authority.
Only literal roc fields in the initial header dependency record are supported.
"""
import re

TOKEN = re.compile(r'#[^\n]*|"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z_0-9!]*|[^\s]', re.DOTALL)
NUMBER = r'(?:0|[1-9][0-9]*)'
IDENTIFIER = rf'(?:{NUMBER}|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
PIN = re.compile(rf'(?:nightly-[0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}}-[0-9a-f]{{7,40}}|{NUMBER}\.{NUMBER}\.{NUMBER}(?:-{IDENTIFIER}(?:\.{IDENTIFIER})*)?)')



def header_pin(source):
    tokens = (match for match in TOKEN.finditer(source) if not match.group().startswith('#'))
    first = next(tokens, None)
    if first is None or first.group() not in {'app', 'package', 'platform'}:
        return None
    platform = first.group() == 'platform'
    stack = []
    packages = not platform
    record = False
    fields = []
    previous = None
    for token in tokens:
        value = token.group()
        if not record:
            if platform and not stack and value == 'packages':
                packages = True
            if packages and not stack and value == '{':
                record = True
                stack.append('}')
                previous = '{'
                continue
            if value in {'[', '{', '('}:
                stack.append({'[': ']', '{': '}', '(': ')'}[value])
            elif value in {']', '}', ')'}:
                if not stack or stack.pop() != value:
                    raise ValueError('Malformed Roc header delimiters')
            continue
        if len(stack) == 1 and value == 'roc' and previous in {'{', ','}:
            colon = next(tokens, None)
            literal = next(tokens, None)
            if colon is None or colon.group() != ':' or literal is None:
                raise ValueError('Malformed Roc compiler pin field')
            spelling = literal.group()
            if not spelling.startswith('"') or not PIN.fullmatch(spelling[1:-1]):
                raise ValueError('Roc compiler pin must be a supported literal version')
            fields.append((literal.start() + 1, literal.end() - 1, spelling[1:-1]))
            previous = spelling
            continue
        if value in {'[', '{', '('}:
            stack.append({'[': ']', '{': '}', '(': ')'}[value])
        elif value in {']', '}', ')'}:
            if not stack or stack.pop() != value:
                raise ValueError('Malformed Roc header delimiters')
            if not stack:
                if len(fields) > 1:
                    raise ValueError('Duplicate Roc compiler pins')
                return fields[0] if fields else None
        previous = value
    if fields:
        raise ValueError('Incomplete pinned Roc root header')
    return None
