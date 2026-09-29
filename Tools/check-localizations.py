#!/usr/bin/env python3
r"""Fails when a UI string in Sources/Wheedgets has no Russian translation.

Finds string literals passed to SwiftUI views, `.help`, and `String(localized:)`,
then compares them with the keys in Resources/ru.lproj/Localizable.strings.
Interpolations like `\(name)` become `%@`, as in the generated lookup key.
"""
import glob
import re
import sys

UI_STRING = re.compile(
    r'(?:String\(localized: |Text\(|Label\(|Button\(|Toggle\(|Section\(|LabeledContent\(|'
    r'Picker\(|TextField\(|\.help\(|help: |navigationTitle\(|prompt: Text\()"((?:[^"\\]|\\.)+)"'
)
TERNARY = re.compile(r'\?\s*"((?:[^"\\]|\\.)+)"\s*:\s*"((?:[^"\\]|\\.)+)"')
TRANSLATION = re.compile(r'^"((?:[^"\\]|\\.)+)"\s*=', re.MULTILINE)
# Ternaries also pick up SF Symbol names, which are not user-visible text.
NOT_TEXT = re.compile(r'^[a-z0-9.]+$')
INTERPOLATION = re.compile(r'\\\([^)]*\)')

keys = set()
for path in glob.glob("Sources/**/*.swift", recursive=True):
    source = open(path, encoding="utf-8").read()
    keys.update(m.group(1) for m in UI_STRING.finditer(source))
    for m in TERNARY.finditer(source):
        keys.update(k for k in m.groups() if not NOT_TEXT.match(k))

# Numbers interpolate as %lld, strings as %@; the source alone can't tell which.
FORMAT = re.compile(r"%(?:@|lld|ld|d)")
translated = {
    FORMAT.sub("%@", key)
    for key in TRANSLATION.findall(open("Resources/ru.lproj/Localizable.strings", encoding="utf-8").read())
}
keys = {INTERPOLATION.sub("%@", key) for key in keys}
missing = sorted(keys - translated)
for key in missing:
    print(f"missing ru translation: {key}")
sys.exit(1 if missing else 0)
