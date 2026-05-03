# Current - macOS App

Current is a native macOS daily stream Markdown editor. MVP 0 focuses on capture: open the app, type or paste messy notes, trust autosave, and scroll through recent history. The UI feels like one continuous stream, while storage stays transparent as plain daily Markdown files.

The project uses a **workspace + SPM package** architecture for clean separation between app shell and feature code.

## MVP 0

- One default stream: **Daily** (`daily` on disk)
- Today plus recent days in a single scrollable timeline
- Transparent storage at `~/Documents/current/streams/daily/YYYY/MM/YYYY-MM-DD.md`
- Configurable base folder with `library-root = ~/Documents/current`
- Generated day dividers in the UI; each Markdown file contains only that day's notes
- AppKit `NSTextView`-backed Markdown editor sections
- Syntax highlighting for headings, lists, checkboxes, links, emphasis, blockquotes, inline code, and fenced code blocks
- Paste handling for plain text, Markdown, rich text, URLs, HTML snippets, and large meeting-note dumps
- Autosave per day file with external edit conflict detection
- Jump to today, insert timestamp, and reveal files

## Project Architecture

```
Current/
├── Current.xcworkspace/              # Open this file in Xcode
├── Current.xcodeproj/                # App shell project
├── Current/                          # App target (minimal)
│   ├── Assets.xcassets/                # App-level assets (icons, colors)
│   ├── CurrentApp.swift              # App entry point
│   ├── Current.entitlements          # App sandbox settings
│   └── Current.xctestplan            # Test configuration
├── CurrentPackage/                   # 🚀 Primary development area
│   ├── Package.swift                   # Package configuration
│   ├── Sources/CurrentFeature/       # Your feature code
│   └── Tests/CurrentFeatureTests/    # Unit tests
└── CurrentUITests/                   # UI automation tests
```

## Key Architecture Points

### Workspace + SPM Structure
- **App Shell**: `Current/` contains minimal app lifecycle code
- **Feature Code**: `CurrentPackage/Sources/CurrentFeature/` is where most development happens
- **Separation**: Business logic lives in the SPM package, app target just imports and displays it

### Buildable Folders (Xcode 16)
- Files added to the filesystem automatically appear in Xcode
- No need to manually add files to project targets
- Reduces project file conflicts in teams

### App Sandbox
The app is sandboxed by default with basic file access permissions. Modify `Current.entitlements` to add capabilities as needed.

## Development Notes

### Website

The standalone static website lives in `website/`. It uses Next.js static export and pnpm.

```sh
pnpm --dir website dev
pnpm --dir website build
```

The public routes are `/` for the landing page and `/settings/` for the configuration reference.

Pushes to `main` deploy the static export to GitHub Pages with `.github/workflows/pages.yml`.

### XcodeBuildMCP

This repo was scaffolded with XcodeBuildMCP and should be built/tested with its CLI tools:

```sh
xcodebuildmcp swift-package build --package-path CurrentPackage
xcodebuildmcp swift-package test --package-path CurrentPackage
xcodebuildmcp swift-package run --package-path CurrentPackage --executable-name CurrentFeatureChecks
xcodebuildmcp macos build --workspace-path Current.xcworkspace --scheme Current
```

`CurrentFeatureChecks` is the environment-independent validation runner for storage, autosave, rollover, cache eviction, and conflict detection. The full macOS app build requires a full Xcode install selected with `xcode-select`; Command Line Tools alone cannot provide `xcodebuild`.

### Code Organization
Most development happens in `CurrentPackage/Sources/CurrentFeature/` - organize your code as you prefer.

### Public API Requirements
Types exposed to the app target need `public` access:
```swift
public struct SettingsView: View {
    public init() {}
    
    public var body: some View {
        // Your view code
    }
}
```

### Adding Dependencies
Edit `CurrentPackage/Package.swift` to add SPM dependencies:
```swift
dependencies: [
    .package(url: "https://github.com/example/SomePackage", from: "1.0.0")
],
targets: [
    .target(
        name: "CurrentFeature",
        dependencies: ["SomePackage"]
    ),
]
```

### Test Structure
- **Unit Tests**: `CurrentPackage/Tests/CurrentFeatureTests/` (Swift Testing framework)
- **UI Tests**: `CurrentUITests/` (XCUITest framework)
- **Test Plan**: `Current.xctestplan` coordinates all tests

## Configuration

### XCConfig Build Settings
Build settings are managed through **XCConfig files** in `Config/`:
- `Config/Shared.xcconfig` - Common settings (bundle ID, versions, deployment target)
- `Config/Debug.xcconfig` - Debug-specific settings  
- `Config/Release.xcconfig` - Release-specific settings
- `Config/Tests.xcconfig` - Test-specific settings

### App Sandbox & Entitlements
The app is sandboxed by default with basic file access. Edit `Current/Current.entitlements` to add capabilities:
```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<!-- Add other entitlements as needed -->
```

## macOS-Specific Features

### Window Management
Add multiple windows and settings panels:
```swift
@main
struct CurrentApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        Settings {
            SettingsView()
        }
    }
}
```

### Asset Management
- **App-Level Assets**: `Current/Assets.xcassets/` (app icon with multiple sizes, accent color)
- **Feature Assets**: Add `Resources/` folder to SPM package if needed

### SPM Package Resources
To include assets in your feature package:
```swift
.target(
    name: "CurrentFeature",
    dependencies: [],
    resources: [.process("Resources")]
)
```

## Notes

### Generated with XcodeBuildMCP
This project was scaffolded using [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), which provides tools for AI-assisted macOS development workflows.
