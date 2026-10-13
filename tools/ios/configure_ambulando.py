#!/usr/bin/env python3
"""Idempotently add Ambulando configuration clones to the shared native targets."""
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / 'app/ios/Runner.xcodeproj/project.pbxproj'

def configure():
    source = PROJECT.read_text()
    if 'Debug-ambulando' in source:
        return
    pattern = r'(\t\t([A-F0-9]{24}) /\* (Debug|Release|Profile) \*/ = \{\n\t\t\tisa = XCBuildConfiguration;.*?\n\t\t\};)'
    clones = []
    ids = {}
    for block, identifier, mode in re.findall(pattern, source, re.S):
        new_id = hashlib.sha256(('ambulando-' + identifier).encode()).hexdigest()[:24].upper()
        ids[identifier] = (new_id, mode)
        clone = block.replace(identifier, new_id).replace(f'/* {mode} */', f'/* {mode}-ambulando */').replace(f'name = {mode};', f'name = "{mode}-ambulando";')
        clone = clone.replace('WMAPP_LAUNCH_SCREEN = LaunchScreen;', 'WMAPP_LAUNCH_SCREEN = AmbulandoLaunch;')
        clone = clone.replace('WMAPP_DISPLAY_NAME = "Wingman App";', 'WMAPP_DISPLAY_NAME = Ambulando;')
        clone = clone.replace('com.wingmanbefree.wingmanApp', 'com.wingmanbefree.ambulando')
        if 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;' in clone:
            clone = clone.replace('ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;', 'ASSETCATALOG_COMPILER_APPICON_NAME = AmbulandoIcon;')
        clones.append(clone)
    if len(clones) != 12:
        raise ValueError('Expected exactly three configurations for project and each shared target')
    source = source.replace('/* End XCBuildConfiguration section */', '\n'.join(clones) + '\n/* End XCBuildConfiguration section */')
    def add_configs(match):
        block = match.group(0)
        additions = []
        for identifier in re.findall(r'([A-F0-9]{24}) /\* (?:Debug|Release|Profile) \*/', block):
            new_id, mode = ids[identifier]
            additions.append(f'\t\t\t\t{new_id} /* {mode}-ambulando */,')
        return block.replace('\n\t\t\t);', '\n' + '\n'.join(additions) + '\n\t\t\t);')
    source = re.sub(r'buildConfigurations = \(.*?\n\t\t\t\);', add_configs, source, flags=re.S)
    PROJECT.write_text(source)
    scheme = ROOT / 'app/ios/Runner.xcodeproj/xcshareddata/xcschemes'
    content = (scheme / 'Runner.xcscheme').read_text()
    for mode in ('Debug', 'Release', 'Profile'):
        content = content.replace(f'buildConfiguration = "{mode}"', f'buildConfiguration = "{mode}-ambulando"')
    (scheme / 'ambulando.xcscheme').write_text(content)

if __name__ == '__main__':
    configure()
