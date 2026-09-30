# Current - macOS App

Current is a native macOS Markdown workspace organized around daily streams. A folder sidebar holds streams such as Daily, Work, and Journal; each opens a continuous timeline of ordinary Markdown files.

## Writing workspace

- Create, rename, reorder, pin, archive, and restore streams; group them in folders.
- Use a compact sidebar and a centered 640-point writing column. Open tabs explicitly, or use focus mode to hide navigation and controls.
- Fold empty historical dates into compact ranges, preview collapsed notes, and see written days in the calendar.
- Read rendered Markdown with proportional text, native tasks, code blocks, tables, and local images. Edit source in place or toggle Markdown Source.
- Use native text input, undo, find, rich-text paste, and relative image attachments.
- Type `[[` to complete a link to an existing stream; folder-qualified names distinguish duplicate names.
- Search history with clean highlighted excerpts, switch streams with folder context, and jump directly to a date.
- Use light, dark, or system appearance. Explicit font settings are preserved.
- Keep notes local at `~/Documents/current/streams/<stream>/YYYY/MM/YYYY-MM-DD.md` by default. Set `library-root` to use another directory.
- Autosave retains document-specific destinations, detects external conflicts, and flushes on normal quit. Dirty recovery records are written after a 150 ms debounce; forced termination can lose the most recent edits before that write completes.

| Action | Shortcut |
| --- | --- |
| Commands | ⌘K |
| Switch stream | ⌘O |
| Search history | ⇧⌘F |
| Find in active day | ⌘F |
| Today | ⇧⌘D |
| Show/hide sidebar | ⌘\ |
| Focus mode | ⇧⌘Return |
| Markdown source | ⇧⌘M |
| New stream | ⌘N |

Daily streams are the primary model. Standalone notes, cloud sync, collaboration, math, and diagram rendering are outside this version. The editor uses native TextKit 1 with a revision-cached rendering model; a complete TextKit 2 migration remains separate work.

The project uses a workspace plus Swift package: the app shell owns lifecycle and menus, while the package contains the editor, library, and interface.

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
The current app configuration is not sandboxed. Entitlements live in `Config/Current.entitlements`.

## Development Notes

### Website

The standalone static website lives in `website/`. It uses Next.js static export and pnpm.

```sh
pnpm --dir website dev
pnpm --dir website build
```

The public routes are `/` for the landing page and `/settings/` for the configuration reference.

Pushes to `main` deploy the static export to GitHub Pages with `.github/workflows/pages.yml`.

### Releases and upgrades

[Current 0.3.0](https://github.com/iamrajjoshi/current/releases/tag/v0.3.0) was published on September 30, 2026, signed with Developer ID and notarized by Apple. Historical version `0.2.0` is unsigned. Releases run manually through GitHub Actions; see [Release setup and upgrade instructions](docs/releases.md) for credentials, branch selection, validation gates, and Homebrew retries.

### Build and validate

Open `Current.xcworkspace` in Xcode to build the app. Package validation can also run with Command Line Tools:

```bash
scripts/validate-local.sh all
scripts/validate-local.sh probe --live --exercise --output /tmp/current-ui-check
```

The script detects the extra Swift Testing search paths required by some CLT installations. Set `CURRENT_BUILD_PATH` to use a separate scratch directory. `CurrentFeatureChecks` covers storage, autosave, rollover, cache eviction, and conflict detection. `CurrentUIProbe` mounts the actual interface and AppKit editor in an isolated temporary library and writes screenshots and a JSON report. It never opens the user's notes or preferences.

The native probe exercises input, undo/redo, marked text, caret visibility, resizing, source mode, appearance, and saving. It supplements unit tests; it isn't a frame-rate benchmark, a full IME certification, or an accessibility audit. Full Xcode app/UI tests still require a configured Xcode installation.

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
The app currently uses an empty `Config/Current.entitlements` file. A future sandboxed distribution would require explicit file-access handling and appropriate entitlements, for example:
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

## License

[MIT](LICENSE)
