export type SettingCategory = "Storage" | "Editor" | "Timeline" | "Saving" | "Markdown";

export type CurrentSetting = {
  key: string;
  category: SettingCategory;
  defaultValue: string;
  acceptedValues: string;
  description: string;
  example: string;
};

export const configLocations = [
  "~/.config/current/config.current",
  "~/.config/current/config",
  "~/Library/Application Support/com.raj.current/config.current",
  "~/Library/Application Support/com.raj.current/config"
] as const;

export const settings: CurrentSetting[] = [
  {
    key: "library-root",
    category: "Storage",
    defaultValue: "Unset, resolves to ~/Documents/current",
    acceptedValues: "Absolute path, ~/ path, or empty value",
    description: "Moves the Current library root while keeping daily stream files transparent on disk.",
    example: "library-root = ~/Documents/current"
  },
  {
    key: "font-family",
    category: "Editor",
    defaultValue: "Unset, uses the macOS monospaced system font",
    acceptedValues: "Installed font family name, quoted or unquoted",
    description: "Overrides the editor font family while preserving Current's plain-text editor behavior.",
    example: "font-family = \"JetBrains Mono\""
  },
  {
    key: "font-size",
    category: "Editor",
    defaultValue: "13",
    acceptedValues: "Number from 6 through 72",
    description: "Controls the AppKit Markdown editor text size.",
    example: "font-size = 13"
  },
  {
    key: "line-height",
    category: "Editor",
    defaultValue: "22",
    acceptedValues: "Number from 8 through 120",
    description: "Controls the editor line box height for calmer daily writing.",
    example: "line-height = 22"
  },
  {
    key: "content-width",
    category: "Editor",
    defaultValue: "700",
    acceptedValues: "Number from 320 through 2000",
    description: "Sets the centered writing column width used by the timeline.",
    example: "content-width = 700"
  },
  {
    key: "recent-days",
    category: "Timeline",
    defaultValue: "7",
    acceptedValues: "Integer from 1 through 3650",
    description: "Controls how many recent days Current loads around today on launch.",
    example: "recent-days = 7"
  },
  {
    key: "history-batch-days",
    category: "Timeline",
    defaultValue: "14",
    acceptedValues: "Integer from 1 through 3650",
    description: "Controls how many older days are added as the timeline reaches the load trigger.",
    example: "history-batch-days = 14"
  },
  {
    key: "history-window-days",
    category: "Timeline",
    defaultValue: "180",
    acceptedValues: "Integer from 1 through 10000",
    description: "Controls the retained in-memory timeline window before older rows become spacer height.",
    example: "history-window-days = 180"
  },
  {
    key: "autosave-delay",
    category: "Saving",
    defaultValue: "0.55",
    acceptedValues: "Number from 0 through 60",
    description: "Sets the debounce delay before a dirty day document is written to disk.",
    example: "autosave-delay = 0.55"
  },
  {
    key: "hide-empty-weekends",
    category: "Timeline",
    defaultValue: "false",
    acceptedValues: "true, false, yes, no, on, off, 1, or 0",
    description: "Skips empty Saturday and Sunday placeholders while keeping existing weekend notes visible.",
    example: "hide-empty-weekends = false"
  },
  {
    key: "markdown-marker-visibility",
    category: "Markdown",
    defaultValue: "muted",
    acceptedValues: "muted",
    description: "Keeps Markdown punctuation visible but visually quiet in the editor.",
    example: "markdown-marker-visibility = muted"
  },
  {
    key: "config-file",
    category: "Storage",
    defaultValue: "None",
    acceptedValues: "Relative path, absolute path, ~/ path, or ?optional path",
    description: "Includes another config file after the current file is parsed. Later included values can override earlier ones.",
    example: "config-file = ?machine.current"
  }
];

export const completeConfigSnippet = `# Current configuration
# Syntax is key = value. Blank lines and whole-line # comments are ignored.
# Empty values reset a setting to Current's default.

library-root = ~/Documents/current
font-family =
font-size = 13
line-height = 22
content-width = 700
recent-days = 7
history-batch-days = 14
history-window-days = 180
autosave-delay = 0.55
hide-empty-weekends = false
markdown-marker-visibility = muted

# Split config into another file:
config-file = extras.current
config-file = ?machine.current`;

export const highlightedSettings = settings.filter((setting) =>
  ["library-root", "font-size", "line-height", "autosave-delay"].includes(setting.key)
);
