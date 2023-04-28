# -*- mode: python ; coding: utf-8 -*-


block_cipher = None


a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[],
    datas=[('assets', './assets')],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)
pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='main',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['icon.icns'],
)
coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='main',
)
app = BUNDLE(
    coll,
    name='main.app',
    icon='icon.icns',
    bundle_identifier=None,
    info_plist={
            'CFBundleDisplayName': 'CrystalRCM',
            'CFBundleName': 'CrystalRCM',
            'CFBundlePackageType': 'APPL',
            'CFBundleSignature': 'CRCM',
            'CFBundleShortVersionString': '0.1.4',
            'CFBundleVersion': '0.1.4',
            'CFBundleExecutable': 'main',
            'CFBundleIconFile': 'icon.icns',
            'CFBundleIdentifier': 'org.pythonmac.unspecified.CrystalRCM',
            'CFBundleInfoDictionaryVersion': '6.0',
    },
)