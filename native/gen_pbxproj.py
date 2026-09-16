#!/usr/bin/env python3
"""Regenerates NoktaStudio.xcodeproj/project.pbxproj from the current file
tree under NoktaStudio/. Run this after adding/removing/renaming source
files. Classic (non file-system-synchronized) pbxproj format for maximum
compatibility.
"""
import os
import hashlib
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.join(ROOT, "NoktaStudio")
PROJ_DIR = os.path.join(ROOT, "NoktaStudio.xcodeproj")
PBXPROJ_PATH = os.path.join(PROJ_DIR, "project.pbxproj")

BUNDLE_ID_BASE = "com.noktastudio.admin"

_counter = [0]
_uuid_cache = {}

def uid(key):
    """Deterministic 24-hex-char id, stable across regenerations for the same key."""
    if key in _uuid_cache:
        return _uuid_cache[key]
    h = hashlib.sha1(key.encode("utf-8")).hexdigest()[:24].upper()
    _uuid_cache[key] = h
    return h

RESOURCE_EXTENSIONS = (".ttf", ".otf")

def collect_files():
    swift_files = []
    resource_files = []
    for dirpath, dirnames, filenames in os.walk(SRC_DIR):
        dirnames.sort()
        rel_dir = os.path.relpath(dirpath, SRC_DIR)
        for fn in sorted(filenames):
            if fn == ".DS_Store":
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.normpath(os.path.join(rel_dir, fn)) if rel_dir != "." else fn
            if fn.endswith(".swift"):
                swift_files.append(rel)
            elif ".xcassets" in full:
                # handled as a single package reference below; skip individual files
                pass
            elif fn.endswith(RESOURCE_EXTENSIONS):
                resource_files.append(rel)
    return swift_files, resource_files

def main():
    swift_files, resource_files = collect_files()
    xcassets_rel = "Assets.xcassets"

    # ---- Fixed object ids ----
    proj_id = uid("project")
    main_group_id = uid("mainGroup")
    app_group_id = uid("group:App")
    core_group_id = uid("group:Core")
    core_net_group_id = uid("group:Core/Networking")
    core_session_group_id = uid("group:Core/Session")
    core_models_group_id = uid("group:Core/Models")
    features_group_id = uid("group:Features")
    features_auth_group_id = uid("group:Features/Auth")
    features_shell_group_id = uid("group:Features/Shell")
    products_group_id = uid("group:Products")

    ios_target_id = uid("target:ios")
    mac_target_id = uid("target:mac")
    ios_product_id = uid("product:ios")
    mac_product_id = uid("product:mac")

    ios_config_list_id = uid("configlist:ios")
    mac_config_list_id = uid("configlist:mac")
    proj_config_list_id = uid("configlist:proj")
    ios_debug_id = uid("config:ios:debug")
    ios_release_id = uid("config:ios:release")
    mac_debug_id = uid("config:mac:debug")
    mac_release_id = uid("config:mac:release")
    proj_debug_id = uid("config:proj:debug")
    proj_release_id = uid("config:proj:release")

    ios_sources_phase_id = uid("phase:ios:sources")
    ios_resources_phase_id = uid("phase:ios:resources")
    ios_frameworks_phase_id = uid("phase:ios:frameworks")
    mac_sources_phase_id = uid("phase:mac:sources")
    mac_resources_phase_id = uid("phase:mac:resources")
    mac_frameworks_phase_id = uid("phase:mac:frameworks")

    xcassets_fileref_id = uid("fileref:Assets.xcassets")
    xcassets_build_ios_id = uid("build:ios:Assets.xcassets")
    xcassets_build_mac_id = uid("build:mac:Assets.xcassets")

    # Map each folder (relative to SRC_DIR) to a group id, creating ids on the fly
    def group_id_for(reldir):
        if reldir in ("", "."):
            return main_group_id
        return uid(f"group:{reldir}")

    # ---- Build file references + build files (compiled into BOTH targets) ----
    fileref_entries = []
    group_children = {}  # reldir -> list of (fileref_id, name)
    build_files_ios = []
    build_files_mac = []

    for rel in swift_files:
        reldir = os.path.dirname(rel)
        name = os.path.basename(rel)
        fref_id = uid(f"fileref:{rel}")
        fileref_entries.append(
            f'\t\t{fref_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};'
        )
        group_children.setdefault(reldir, []).append((fref_id, name))

        bf_ios = uid(f"build:ios:{rel}")
        bf_mac = uid(f"build:mac:{rel}")
        build_files_ios.append((bf_ios, fref_id, name))
        build_files_mac.append((bf_mac, fref_id, name))

    # ---- Resource files (fonts etc.) — compiled into Resources phase, both targets ----
    resource_build_files_ios = []
    resource_build_files_mac = []
    for rel in resource_files:
        reldir = os.path.dirname(rel)
        name = os.path.basename(rel)
        fref_id = uid(f"fileref:{rel}")
        fileref_entries.append(
            f'\t\t{fref_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = file; path = {name}; sourceTree = "<group>"; }};'
        )
        group_children.setdefault(reldir, []).append((fref_id, name))

        bf_ios = uid(f"build:ios:res:{rel}")
        bf_mac = uid(f"build:mac:res:{rel}")
        resource_build_files_ios.append((bf_ios, fref_id, name))
        resource_build_files_mac.append((bf_mac, fref_id, name))

    # ---- Groups (recursive, only for directories that actually contain files) ----
    all_dirs = set(group_children.keys())
    # ensure parent dirs exist even if they only contain subfolders
    expanded = set(all_dirs)
    for d in list(all_dirs):
        parts = d.split(os.sep) if d not in ("", ".") else []
        cur = ""
        for p in parts:
            cur = p if cur == "" else os.path.join(cur, p)
            expanded.add(cur)
    all_dirs = expanded

    def children_of(reldir):
        subdirs = set()
        for d in all_dirs:
            if d in ("", "."):
                continue
            parent = os.path.dirname(d)
            if parent == "" and reldir in ("", "."):
                subdirs.add(d)
            elif parent == reldir:
                subdirs.add(d)
        return sorted(subdirs)

    group_entries = []

    def emit_group(reldir):
        gid = group_id_for(reldir)
        name = os.path.basename(reldir) if reldir not in ("", ".") else None
        child_ids = []
        for sub in children_of(reldir):
            child_ids.append(group_id_for(sub))
            emit_group(sub)
        for fref_id, fname in sorted(group_children.get(reldir, []), key=lambda x: x[1]):
            child_ids.append(fref_id)
        lines = [f'\t\t{gid} = {{', '\t\t\tisa = PBXGroup;', '\t\t\tchildren = (']
        for cid in child_ids:
            lines.append(f'\t\t\t\t{cid},')
        lines.append('\t\t\t);')
        if name:
            lines.append(f'\t\t\tpath = "{name}";')
        lines.append('\t\t\tsourceTree = "<group>";')
        lines.append('\t\t};')
        group_entries.append("\n".join(lines))

    emit_group("")

    # ---- Assemble PBXBuildFile section ----
    buildfile_lines = []
    for bf_id, fref_id, name in build_files_ios:
        buildfile_lines.append(f'\t\t{bf_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref_id} /* {name} */; }};')
    for bf_id, fref_id, name in build_files_mac:
        buildfile_lines.append(f'\t\t{bf_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref_id} /* {name} */; }};')
    buildfile_lines.append(f'\t\t{xcassets_build_ios_id} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {xcassets_fileref_id} /* Assets.xcassets */; }};')
    buildfile_lines.append(f'\t\t{xcassets_build_mac_id} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {xcassets_fileref_id} /* Assets.xcassets */; }};')
    for bf_id, fref_id, name in resource_build_files_ios:
        buildfile_lines.append(f'\t\t{bf_id} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {fref_id} /* {name} */; }};')
    for bf_id, fref_id, name in resource_build_files_mac:
        buildfile_lines.append(f'\t\t{bf_id} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {fref_id} /* {name} */; }};')

    # ---- Root-level file refs (Assets.xcassets, products) ----
    fileref_entries.append(
        f'\t\t{xcassets_fileref_id} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};'
    )
    fileref_entries.append(
        f'\t\t{ios_product_id} /* NoktaStudio.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "NoktaStudio.app"; sourceTree = BUILT_PRODUCTS_DIR; }};'
    )
    fileref_entries.append(
        f'\t\t{mac_product_id} /* NoktaStudio.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "NoktaStudio.app"; sourceTree = BUILT_PRODUCTS_DIR; }};'
    )

    # top-level group needs Assets.xcassets + Products group added as children of root
    # (main_group_id is the "" group emitted above; patch it by re-emitting with extras)
    # Simplify: rebuild root group entry manually replacing the auto one.
    root_children = []
    for sub in children_of(""):
        root_children.append(group_id_for(sub))
    root_children.append(xcassets_fileref_id)
    root_children.append(products_group_id)
    # remove the auto-generated root group text and replace
    group_entries = [g for g in group_entries if not g.startswith(f'\t\t{main_group_id} =')]
    root_lines = [f'\t\t{main_group_id} = {{', '\t\t\tisa = PBXGroup;', '\t\t\tchildren = (']
    for cid in root_children:
        root_lines.append(f'\t\t\t\t{cid},')
    root_lines.append('\t\t\t);')
    root_lines.append('\t\t\tpath = NoktaStudio;')
    root_lines.append('\t\t\tsourceTree = "<group>";')
    root_lines.append('\t\t};')
    group_entries.insert(0, "\n".join(root_lines))

    products_group_text = (
        f'\t\t{products_group_id} = {{\n'
        f'\t\t\tisa = PBXGroup;\n'
        f'\t\t\tchildren = (\n'
        f'\t\t\t\t{ios_product_id} /* NoktaStudio.app */,\n'
        f'\t\t\t\t{mac_product_id} /* NoktaStudio.app */,\n'
        f'\t\t\t);\n'
        f'\t\t\tname = Products;\n'
        f'\t\t\tsourceTree = "<group>";\n'
        '\t\t};'
    )
    group_entries.append(products_group_text)

    # ---- Sources build phases ----
    ios_sources_lines = "\n".join(f'\t\t\t\t{bf_id} /* {name} in Sources */,' for bf_id, _, name in build_files_ios)
    mac_sources_lines = "\n".join(f'\t\t\t\t{bf_id} /* {name} in Sources */,' for bf_id, _, name in build_files_mac)
    ios_resource_lines = "\n".join(f'\t\t\t\t{bf_id} /* {name} in Resources */,' for bf_id, _, name in resource_build_files_ios)
    mac_resource_lines = "\n".join(f'\t\t\t\t{bf_id} /* {name} in Resources */,' for bf_id, _, name in resource_build_files_mac)

    pbx = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(buildfile_lines)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(fileref_entries)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{ios_frameworks_phase_id} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{mac_frameworks_phase_id} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{chr(10).join(group_entries)}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{ios_target_id} /* NoktaStudio-iOS */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {ios_config_list_id} /* Build configuration list for PBXNativeTarget "NoktaStudio-iOS" */;
\t\t\tbuildPhases = (
\t\t\t\t{ios_sources_phase_id} /* Sources */,
\t\t\t\t{ios_frameworks_phase_id} /* Frameworks */,
\t\t\t\t{ios_resources_phase_id} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = "NoktaStudio-iOS";
\t\t\tproductName = "NoktaStudio-iOS";
\t\t\tproductReference = {ios_product_id} /* NoktaStudio.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{mac_target_id} /* NoktaStudio-macOS */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {mac_config_list_id} /* Build configuration list for PBXNativeTarget "NoktaStudio-macOS" */;
\t\t\tbuildPhases = (
\t\t\t\t{mac_sources_phase_id} /* Sources */,
\t\t\t\t{mac_frameworks_phase_id} /* Frameworks */,
\t\t\t\t{mac_resources_phase_id} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = "NoktaStudio-macOS";
\t\t\tproductName = "NoktaStudio-macOS";
\t\t\tproductReference = {mac_product_id} /* NoktaStudio.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{proj_id} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1540;
\t\t\t\tLastUpgradeCheck = 1540;
\t\t\t}};
\t\t\tbuildConfigurationList = {proj_config_list_id} /* Build configuration list for PBXProject "NoktaStudio" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group_id};
\t\t\tproductRefGroup = {products_group_id} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{ios_target_id} /* NoktaStudio-iOS */,
\t\t\t\t{mac_target_id} /* NoktaStudio-macOS */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{ios_resources_phase_id} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{xcassets_build_ios_id} /* Assets.xcassets in Resources */,
{ios_resource_lines}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{mac_resources_phase_id} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{xcassets_build_mac_id} /* Assets.xcassets in Resources */,
{mac_resource_lines}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{ios_sources_phase_id} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{ios_sources_lines}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{mac_sources_phase_id} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{mac_sources_lines}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{proj_debug_id} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{proj_release_id} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Owholemodule";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{ios_debug_id} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = 3J4T38GS8V;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleLightContent;
				INFOPLIST_KEY_UIViewControllerBasedStatusBarAppearance = NO;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 27.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "{BUNDLE_ID_BASE}.ios";
\t\t\t\tPRODUCT_NAME = "NoktaStudio";
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Nokta Studio";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{ios_release_id} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = 3J4T38GS8V;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleLightContent;
				INFOPLIST_KEY_UIViewControllerBasedStatusBarAppearance = NO;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 27.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "{BUNDLE_ID_BASE}.ios";
\t\t\t\tPRODUCT_NAME = "NoktaStudio";
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Nokta Studio";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{mac_debug_id} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = 3J4T38GS8V;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 27.0;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "{BUNDLE_ID_BASE}.mac";
\t\t\t\tPRODUCT_NAME = "NoktaStudio";
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Nokta Studio";
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{mac_release_id} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = 3J4T38GS8V;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 27.0;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "{BUNDLE_ID_BASE}.mac";
\t\t\t\tPRODUCT_NAME = "NoktaStudio";
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Nokta Studio";
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{proj_config_list_id} /* Build configuration list for PBXProject "NoktaStudio" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{proj_debug_id} /* Debug */,
\t\t\t\t{proj_release_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{ios_config_list_id} /* Build configuration list for PBXNativeTarget "NoktaStudio-iOS" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{ios_debug_id} /* Debug */,
\t\t\t\t{ios_release_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{mac_config_list_id} /* Build configuration list for PBXNativeTarget "NoktaStudio-macOS" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{mac_debug_id} /* Debug */,
\t\t\t\t{mac_release_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {proj_id} /* Project object */;
}}
"""

    os.makedirs(PROJ_DIR, exist_ok=True)
    with open(PBXPROJ_PATH, "w") as f:
        f.write(pbx)
    print(f"Wrote {PBXPROJ_PATH} with {len(swift_files)} swift files and {len(resource_files)} resource files.")
    for s in swift_files:
        print("  -", s)
    for r in resource_files:
        print("  * (resource)", r)

if __name__ == "__main__":
    main()
