#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project using stable IDs."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent
def uid(label):
    return hashlib.sha256(label.encode()).hexdigest()[:24].upper()
def q(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'

app_sources = sorted(str(p.relative_to(root)) for p in (root / 'ScreenTranslate').rglob('*.swift'))
unit_sources = sorted(str(p.relative_to(root)) for p in (root / 'Tests/ScreenTranslateCoreTests').glob('*.swift'))
unit_sources += sorted(str(p.relative_to(root)) for p in (root / 'Tests/iOSTests').glob('*.swift'))
ui_sources = sorted(str(p.relative_to(root)) for p in (root / 'Tests/UITests').glob('*.swift'))
objects = []
def obj(key, value):
    objects.append(f'\t\t{uid(key)} = {{ {value} }};')
def arr(items):
    return '(' + ', '.join(items) + ')'

resources = ['ScreenTranslate/Assets.xcassets', 'ScreenTranslate/PrivacyInfo.xcprivacy', 'ScreenTranslate/Resources/屏译全文.shortcut', 'ScreenTranslate/Resources/读屏全文.shortcut', 'ScreenTranslate/Resources/en.lproj', 'ScreenTranslate/Resources/zh-Hans.lproj']
test_resources = ['Tests/Fixtures/menu-screenshot.jpg']
test_resources += sorted(str(p.relative_to(root)) for p in (root / 'Tests/Fixtures/generated-ja-en-v1').glob('*.png'))
for source in app_sources + unit_sources + ui_sources + resources + test_resources:
    filetype = 'sourcecode.swift' if source.endswith('.swift') else ('folder.assetcatalog' if source.endswith('.xcassets') else ('text.xml' if source.endswith('.xcprivacy') else ('folder' if source.endswith('.lproj') else 'file')))
    obj('file:' + source, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = {q(source)}; sourceTree = SOURCE_ROOT;')
for name, producttype, suffix in [('ScreenTranslate', 'wrapper.application', '.app'), ('ScreenTranslateTests', 'wrapper.cfbundle', '.xctest'), ('ScreenTranslateUITests', 'wrapper.cfbundle', '.xctest')]:
    obj('product:' + name, f'isa = PBXFileReference; explicitFileType = {producttype}; path = {q(name + suffix)}; sourceTree = BUILT_PRODUCTS_DIR;')

obj('products', 'isa = PBXGroup; name = Products; children = ' + arr(uid('product:' + n) for n in ['ScreenTranslate', 'ScreenTranslateTests', 'ScreenTranslateUITests']) + '; sourceTree = "<group>";')
obj('main', 'isa = PBXGroup; children = ' + arr([*(uid('file:' + p) for p in app_sources + unit_sources + ui_sources + resources + test_resources), uid('products')]) + '; sourceTree = "<group>";')

for name, sources, product_type in [
    ('ScreenTranslate', app_sources, 'com.apple.product-type.application'),
    ('ScreenTranslateTests', unit_sources, 'com.apple.product-type.bundle.unit-test'),
    ('ScreenTranslateUITests', ui_sources, 'com.apple.product-type.bundle.ui-testing')]:
    for source in sources:
        obj('build:' + name + ':' + source, f'isa = PBXBuildFile; fileRef = {uid("file:" + source)};')
    obj('sources:' + name, 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ' + arr(uid('build:' + name + ':' + p) for p in sources) + '; runOnlyForDeploymentPostprocessing = 0;')
    obj('frameworks:' + name, 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    items = []
    if name == 'ScreenTranslate':
        for resource in resources:
            obj('resource:' + resource, f'isa = PBXBuildFile; fileRef = {uid("file:" + resource)};')
            items.append(uid('resource:' + resource))
    if name == 'ScreenTranslateTests':
        for resource in test_resources:
            obj('resource:' + resource, f'isa = PBXBuildFile; fileRef = {uid("file:" + resource)};')
            items.append(uid('resource:' + resource))
    obj('resources:' + name, 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ' + arr(items) + '; runOnlyForDeploymentPostprocessing = 0;')
    dependencies = []
    if name != 'ScreenTranslate':
        obj('proxy:' + name, f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("target:ScreenTranslate")}; remoteInfo = ScreenTranslate;')
        obj('dependency:' + name, f'isa = PBXTargetDependency; target = {uid("target:ScreenTranslate")}; targetProxy = {uid("proxy:" + name)};')
        dependencies.append(uid('dependency:' + name))
    for mode in ['Debug', 'Release']:
        settings = {
            'PRODUCT_NAME': '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.raydon.' + name,
            'SWIFT_VERSION': '5.0', 'IPHONEOS_DEPLOYMENT_TARGET': '18.0', 'SDKROOT': 'iphoneos',
            'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'TARGETED_DEVICE_FAMILY': '1',
            'CODE_SIGN_STYLE': 'Automatic', 'GENERATE_INFOPLIST_FILE': 'YES',
            'SWIFT_EMIT_LOC_STRINGS': 'YES', 'ENABLE_PREVIEWS': 'YES',
            'SWIFT_STRICT_CONCURRENCY': 'complete',
        }
        if name == 'ScreenTranslate':
            settings.update({'INFOPLIST_FILE': 'ScreenTranslate/Info.plist', 'GENERATE_INFOPLIST_FILE': 'NO',
                             'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
                             'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor',
                             'MARKETING_VERSION': '1.0.0', 'CURRENT_PROJECT_VERSION': '17',
                             'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks'})
        elif name == 'ScreenTranslateTests':
            settings.update({'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/ScreenTranslate.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ScreenTranslate',
                             'BUNDLE_LOADER': '$(TEST_HOST)', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @loader_path/Frameworks'})
        else:
            settings.update({'TEST_TARGET_NAME': 'ScreenTranslate'})
        if mode == 'Debug':
            settings.update({'SWIFT_OPTIMIZATION_LEVEL': '-Onone', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG $(inherited)', 'ENABLE_TESTABILITY': 'YES'})
        obj('config:' + name + ':' + mode, 'isa = XCBuildConfiguration; buildSettings = { ' + ' '.join(f'{k} = {q(v)};' for k, v in settings.items()) + ' }; name = ' + mode + ';')
    obj('configs:' + name, 'isa = XCConfigurationList; buildConfigurations = ' + arr(uid('config:' + name + ':' + mode) for mode in ['Debug', 'Release']) + '; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    obj('target:' + name, f'isa = PBXNativeTarget; buildConfigurationList = {uid("configs:" + name)}; buildPhases = ' + arr(uid(k + ':' + name) for k in ['sources', 'frameworks', 'resources']) + '; buildRules = (); dependencies = ' + arr(dependencies) + f'; name = {name}; productName = {name}; productReference = {uid("product:" + name)}; productType = {q(product_type)};')

for mode in ['Debug', 'Release']:
    settings = {'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES',
                'GCC_C_LANGUAGE_STANDARD': 'gnu17', 'DEBUG_INFORMATION_FORMAT': 'dwarf' if mode == 'Debug' else 'dwarf-with-dsym',
                'SWIFT_COMPILATION_MODE': 'singlefile' if mode == 'Debug' else 'wholemodule',
                'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode == 'Debug' else '-O'}
    obj('projectconfig:' + mode, 'isa = XCBuildConfiguration; buildSettings = { ' + ' '.join(f'{k} = {q(v)};' for k, v in settings.items()) + ' }; name = ' + mode + ';')
obj('projectconfigs', 'isa = XCConfigurationList; buildConfigurations = ' + arr(uid('projectconfig:' + m) for m in ['Debug', 'Release']) + '; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('project', 'isa = PBXProject; attributes = { BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1620; }; ' + f'buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base); mainGroup = {uid("main")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ' + arr(uid('target:' + n) for n in ['ScreenTranslate', 'ScreenTranslateTests', 'ScreenTranslateUITests']) + ';')
project_dir = root / 'ScreenTranslate.xcodeproj'
project_dir.mkdir(exist_ok=True)
(project_dir / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + '\n\t};\n\trootObject = ' + uid('project') + ';\n}\n')

def buildable(name, suffix):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:" + name)}" BuildableName="{name}{suffix}" BlueprintName="{name}" ReferencedContainer="container:ScreenTranslate.xcodeproj"/>'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1620" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable('ScreenTranslate', '.app')}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
<TestableReference skipped="NO" parallelizable="NO">{buildable('ScreenTranslateTests', '.xctest')}</TestableReference>
<TestableReference skipped="NO" parallelizable="NO">{buildable('ScreenTranslateUITests', '.xctest')}</TestableReference>
</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('ScreenTranslate', '.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('ScreenTranslate', '.app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
scheme_dir = project_dir / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / 'ScreenTranslate.xcscheme').write_text(scheme)
print(f'Generated project with {len(app_sources)} app sources, {len(unit_sources)} unit-test sources and {len(ui_sources)} UI-test sources.')
