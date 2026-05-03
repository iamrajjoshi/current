# Contributing

Thanks for your interest in contributing to Current!

## Getting Started

Prerequisites: macOS with Xcode 16+, Node.js/npm, and XcodeBuildMCP.

```sh
npm install --global xcodebuildmcp@2.3.2
xcodebuildmcp swift-package build --package-path CurrentPackage
xcodebuildmcp swift-package test --package-path CurrentPackage
xcodebuildmcp swift-package run --package-path CurrentPackage --executable-name CurrentFeatureChecks
xcodebuildmcp macos build --workspace-path Current.xcworkspace --scheme Current
```

## Pull Requests

1. Fork the repo and create a branch from `main`.
2. If you've added code that should be tested, add tests.
3. Make sure the Swift package checks and macOS app build pass.
4. Open a pull request.

For new features, please open an issue first to discuss the change.

## Bug Reports

Open a [bug report](https://github.com/iamrajjoshi/current/issues/new?template=bug_report.md) with steps to reproduce.

## Code Style

Follow standard Swift and SwiftUI conventions. Keep changes focused, prefer the existing workspace and SPM package structure, and use the repo's XcodeBuildMCP commands for validation.

## License

By submitting a contribution, you agree that your work will be licensed under the project's [MIT License](./LICENSE).
