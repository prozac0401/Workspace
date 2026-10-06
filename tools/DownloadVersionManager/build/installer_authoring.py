"""Separate verified EXE provenance from MSI privilege authoring.

Summary writes apply only to newly built artifact MSIs. No installation is run.
"""
from __future__ import annotations
import ctypes as C
from ctypes import wintypes as W
import re

COMPILE_RECIPE = 'build/build-watcher.py'
PID_WORDCOUNT = 15
VT_I4 = 3


def compile_source_provenance(recorded, current, snapshot_sha256=None):
    """Require exact app inputs and explicitly preserve an older compile recipe."""
    if not isinstance(recorded, dict) or not isinstance(current, dict):
        raise RuntimeError('Compile source fingerprints must be objects.')
    if set(recorded) != set(current) or COMPILE_RECIPE not in recorded:
        raise RuntimeError('Compile source fingerprint keys changed.')
    if any(not isinstance(value, str) or not re.fullmatch(r'[0-9a-f]{64}', value)
           for value in list(recorded.values()) + list(current.values())):
        raise RuntimeError('Compile source fingerprint is not a SHA-256 value.')
    for name in recorded:
        if name != COMPILE_RECIPE and recorded[name] != current[name]:
            raise RuntimeError('Production application input changed: ' + name)
    changed = recorded[COMPILE_RECIPE] != current[COMPILE_RECIPE]
    if snapshot_sha256 is not None and snapshot_sha256 != recorded[COMPILE_RECIPE]:
        raise RuntimeError('Compile recipe snapshot differs from the original compile manifest.')
    if changed and snapshot_sha256 is None:
        raise RuntimeError('Changed packaging recipe requires an exact compile-recipe snapshot.')
    return {
        'applicationSources': {name: value for name, value in recorded.items() if name != COMPILE_RECIPE},
        'compileRecipeSha256': recorded[COMPILE_RECIPE],
        'packagingRecipeSha256': current[COMPILE_RECIPE],
        'recipeChanged': changed,
        'snapshotVerified': snapshot_sha256 is not None,
    }


def _summary_api():
    msi = C.WinDLL('msi', use_last_error=True)
    msi.MsiGetSummaryInformationW.argtypes = [W.UINT, W.LPCWSTR, W.UINT, C.POINTER(W.UINT)]
    msi.MsiGetSummaryInformationW.restype = W.UINT
    msi.MsiSummaryInfoGetPropertyW.argtypes = [W.UINT, W.UINT, C.POINTER(W.UINT), C.POINTER(C.c_int), C.POINTER(W.FILETIME), W.LPWSTR, C.POINTER(W.DWORD)]
    msi.MsiSummaryInfoGetPropertyW.restype = W.UINT
    msi.MsiSummaryInfoSetPropertyW.argtypes = [W.UINT, W.UINT, W.UINT, C.c_int, C.POINTER(W.FILETIME), W.LPCWSTR]
    msi.MsiSummaryInfoSetPropertyW.restype = W.UINT
    msi.MsiSummaryInfoPersist.argtypes = [W.UINT]
    msi.MsiSummaryInfoPersist.restype = W.UINT
    msi.MsiCloseHandle.argtypes = [W.UINT]
    msi.MsiCloseHandle.restype = W.UINT
    return msi


def _check(code, operation):
    if code:
        raise RuntimeError(operation + ' failed: ' + str(code))


def _word_count(msi, handle):
    kind = W.UINT(); value = C.c_int(); count = W.DWORD()
    _check(msi.MsiSummaryInfoGetPropertyW(handle, PID_WORDCOUNT, C.byref(kind), C.byref(value), None, None, C.byref(count)), 'Read MSI WordCount')
    if kind.value != VT_I4:
        raise RuntimeError('MSI WordCount must have type VT_I4.')
    return value.value


def summary_word_count(path, *, _api=None):
    """Read a VT_I4 WordCount with updateCount=0; execute no MSI actions."""
    msi = _summary_api() if _api is None else _api
    handle = W.UINT()
    _check(msi.MsiGetSummaryInformationW(0, str(path), 0, C.byref(handle)), 'Open read-only MSI summary')
    try:
        return _word_count(msi, handle.value)
    finally:
        _check(msi.MsiCloseHandle(handle.value), 'Close MSI summary')


def author_elevated_per_user(path, *, _api=None):
    """Allow elevation without changing MSI scope, tables, or embedded payload.

    WiX 4 perUser output has WordCount 10. Clear only its no-elevation bit;
    per-user scope remains subject to independent Property table verification.
    https://learn.microsoft.com/windows/win32/msi/word-count-summary
    """
    msi = _summary_api() if _api is None else _api
    handle = W.UINT()
    _check(msi.MsiGetSummaryInformationW(0, str(path), 1, C.byref(handle)), 'Open MSI summary for authoring')
    try:
        before = _word_count(msi, handle.value)
        if before != 10:
            raise RuntimeError('Expected newly built WiX per-user WordCount 10, observed ' + str(before))
        _check(msi.MsiSummaryInfoSetPropertyW(handle.value, PID_WORDCOUNT, VT_I4, 2, None, None), 'Author MSI WordCount 2')
        _check(msi.MsiSummaryInfoPersist(handle.value), 'Persist authored MSI summary')
    finally:
        _check(msi.MsiCloseHandle(handle.value), 'Close authored MSI summary')
    after = summary_word_count(path, _api=msi)
    if after != 2:
        raise RuntimeError('Persisted MSI WordCount readback differs from 2.')
    return {'wordCountBefore': before, 'wordCountAfter': after,
            'elevationAllowed': True, 'readbackVerified': True,
            'api': 'MsiSummaryInfoSetPropertyW/MsiSummaryInfoPersist'}
