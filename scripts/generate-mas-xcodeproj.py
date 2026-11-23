#!/usr/bin/env python3
"""
Generates a clean, self-contained Xcode project (XShot.xcodeproj) configured for
Mac App Store (MAS) Universal Binary (arm64 + x86_64) distribution with App Sandbox.

Zero external dependencies (Python 3 stdlib only).
"""

import argparse
import hashlib
import os
import plistlib
from pathlib import Path


def make_id(seed: str) -> str:
    return hashlib.sha1(seed.encode("utf-8")).hexdigest()[:24].upper()


def read_version_from_plist(plist_path: Path) -> tuple[str, str]:
    with plist_path.open("rb") as f:
        data = plistlib.load(f)
    short_ver = str(data.get("CFBundleShortVersionString", "1.0.0"))
    build_ver = str(data.get("CFBundleVersion", "1"))
    return short_ver, build_ver


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate XShot.xcodeproj for Mac App Store")
    parser.add_argument("--team", default="", help="Optional Apple Developer Team ID (leave empty for open-source default)")
    parser.add_argument("--bundle-id", default="top.xtags.xshot", help="CFBundleIdentifier")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    sources_dir = root / "Sources" / "XShot"
    swift_files = sorted(
        p.relative_to(root).as_posix()
        for p in sources_dir.rglob("*.swift")
    )
    if not swift_files:
        raise SystemExit("No Swift source files found under Sources/XShot")

    short_ver, build_ver = read_version_from_plist(root / "Resources" / "Info.plist")

    # Deterministic 24-hex Xcode object IDs
    project_id = make_id("project:XShot")
    main_group_id = make_id("group:main")
    sources_group_id = make_id("group:Sources")
    resources_group_id = make_id("group:Resources")
    products_group_id = make_id("group:Products")
    target_id = make_id("target:XShot")
    product_ref_id = make_id("fileref:XShot.app")
    sources_phase_id = make_id("phase:Sources")
    resources_phase_id = make_id("phase:Resources")
    frameworks_phase_id = make_id("phase:Frameworks")
    proj_cfg_list_id = make_id("cfglist:project")
    proj_debug_id = make_id("cfg:project:Debug")
    proj_release_id = make_id("cfg:project:Release")
    tgt_cfg_list_id = make_id("cfglist:target")
    tgt_debug_id = make_id("cfg:target:Debug")
    tgt_release_id = make_id("cfg:target:Release")

    assets_ref_id = make_id("fileref:Resources/Assets.xcassets")
    assets_build_id = make_id("buildfile:Resources/Assets.xcassets")
    plist_ref_id = make_id("fileref:Resources/Info-MAS.plist")
    entitlements_ref_id = make_id("fileref:Resources/XShot-MAS.entitlements")
    storekit_ref_id = make_id("fileref:Resources/XShot.storekit")

    file_refs_lines: list[str] = []
    build_files_lines: list[str] = []
    sources_phase_entries: list[str] = []
    sources_group_entries: list[str] = []

    for rel_path in swift_files:
        name = os.path.basename(rel_path)
        fref = make_id(f"fileref:{rel_path}")
        bfile = make_id(f"buildfile:{rel_path}")
        file_refs_lines.append(
            f'\t\t{fref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = "{name}"; path = "{rel_path}"; sourceTree = SOURCE_ROOT; }};'
        )
        build_files_lines.append(
            f'\t\t{bfile} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {name} */; }};'
        )
        sources_phase_entries.append(f"\t\t\t\t{bfile} /* {name} in Sources */,")
        sources_group_entries.append(f"\t\t\t\t{fref} /* {name} */,")

    # Resource file references
    file_refs_lines.extend([
        f'\t\t{assets_ref_id} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; name = "Assets.xcassets"; path = "Resources/Assets.xcassets"; sourceTree = SOURCE_ROOT; }};',
        f'\t\t{plist_ref_id} /* Info-MAS.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; name = "Info-MAS.plist"; path = "Resources/Info-MAS.plist"; sourceTree = SOURCE_ROOT; }};',
        f'\t\t{entitlements_ref_id} /* XShot-MAS.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; name = "XShot-MAS.entitlements"; path = "Resources/XShot-MAS.entitlements"; sourceTree = SOURCE_ROOT; }};',
        f'\t\t{storekit_ref_id} /* XShot.storekit */ = {{isa = PBXFileReference; lastKnownFileType = text; name = "XShot.storekit"; path = "Resources/XShot.storekit"; sourceTree = SOURCE_ROOT; }};',
        f'\t\t{product_ref_id} /* XShot.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = XShot.app; sourceTree = BUILT_PRODUCTS_DIR; }};',
    ])
    build_files_lines.append(
        f'\t\t{assets_build_id} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_ref_id} /* Assets.xcassets */; }};'
    )

    frameworks = [
        "AppKit", "SwiftUI", "ScreenCaptureKit", "AVFoundation",
        "CoreMedia", "CoreVideo", "CoreImage", "CoreGraphics",
        "VideoToolbox", "Metal", "Carbon", "ImageIO",
        "UniformTypeIdentifiers", "Vision", "CryptoKit", "StoreKit",
    ]
    ld_flags = " ".join(f"-framework {fw}" for fw in frameworks)
    team_line = f'\t\t\t\tDEVELOPMENT_TEAM = "{args.team}";'

    pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files_lines)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_refs_lines)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{frameworks_phase_id} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{main_group_id} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{sources_group_id} /* Sources */,
\t\t\t\t{resources_group_id} /* Resources */,
\t\t\t\t{products_group_id} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{sources_group_id} /* Sources */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join(sources_group_entries)}
\t\t\t);
\t\t\tname = Sources;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{resources_group_id} /* Resources */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{assets_ref_id} /* Assets.xcassets */,
\t\t\t\t{plist_ref_id} /* Info-MAS.plist */,
\t\t\t\t{entitlements_ref_id} /* XShot-MAS.entitlements */,
\t\t\t\t{storekit_ref_id} /* XShot.storekit */,
\t\t\t);
\t\t\tname = Resources;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{products_group_id} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{product_ref_id} /* XShot.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{target_id} /* XShot */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {tgt_cfg_list_id} /* Build configuration list for PBXNativeTarget "XShot" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase_id} /* Sources */,
\t\t\t\t{frameworks_phase_id} /* Frameworks */,
\t\t\t\t{resources_phase_id} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = XShot;
\t\t\tproductName = XShot;
\t\t\tproductReference = {product_ref_id} /* XShot.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project_id} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{target_id} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {proj_cfg_list_id} /* Build configuration list for PBXProject "XShot" */;
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
\t\t\t\t{target_id} /* XShot */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{resources_phase_id} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{assets_build_id} /* Assets.xcassets in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{sources_phase_id} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(sources_phase_entries)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{proj_debug_id} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tARCHS = "$(ARCHS_STANDARD)";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.0;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG MAC_APP_STORE";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{proj_release_id} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tARCHS = "$(ARCHS_STANDARD)";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.0;
\t\t\t\tONLY_ACTIVE_ARCH = NO;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "MAC_APP_STORE";
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{tgt_debug_id} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "Resources/XShot-MAS.entitlements";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = "{build_ver}";
{team_line}
\t\t\t\tENABLE_APP_SANDBOX = YES;
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = "Resources/Info-MAS.plist";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = "{short_ver}";
\t\t\t\tOTHER_LDFLAGS = "{ld_flags}";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "{args.bundle_id}";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) MAC_APP_STORE";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{tgt_release_id} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "Resources/XShot-MAS.entitlements";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = "{build_ver}";
{team_line}
\t\t\t\tENABLE_APP_SANDBOX = YES;
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = "Resources/Info-MAS.plist";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = "{short_ver}";
\t\t\t\tOTHER_LDFLAGS = "{ld_flags}";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "{args.bundle_id}";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) MAC_APP_STORE";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{proj_cfg_list_id} /* Build configuration list for PBXProject "XShot" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{proj_debug_id} /* Debug */,
\t\t\t\t{proj_release_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{tgt_cfg_list_id} /* Build configuration list for PBXNativeTarget "XShot" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{tgt_debug_id} /* Debug */,
\t\t\t\t{tgt_release_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {project_id} /* Project object */;
}}
"""

    scheme_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "XShot.app"
               BlueprintName = "XShot"
               ReferencedContainer = "container:XShot.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "XShot.app"
            BlueprintName = "XShot"
            ReferencedContainer = "container:XShot.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
      <StoreKitConfigurationFileReference
         identifier = "../../Resources/XShot.storekit">
      </StoreKitConfigurationFileReference>
   </LaunchAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

    xcodeproj_dir = root / "XShot.xcodeproj"
    schemes_dir = xcodeproj_dir / "xcshareddata" / "xcschemes"
    schemes_dir.mkdir(parents=True, exist_ok=True)
    (xcodeproj_dir / "project.pbxproj").write_text(pbxproj, encoding="utf-8")
    (schemes_dir / "XShot.xcscheme").write_text(scheme_xml, encoding="utf-8")
    print(f"✅ Generated {xcodeproj_dir} ({len(swift_files)} Swift files, v{short_ver} build {build_ver}, MAS Universal)")


if __name__ == "__main__":
    main()
