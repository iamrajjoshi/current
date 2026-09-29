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
    description: "Sets the folder used to store your notes.",
    example: "library-root = ~/Documents/current"
  },
  {
    key: "font-family",
    category: "Editor",
    defaultValue: "Unset, uses the macOS proportional system font",
    acceptedValues: "Installed font family name, quoted or unquoted",
    description: "Sets the font used for note text.",
    example: "font-family = \"JetBrains Mono\""
  },
  {
    key: "font-size",
    category: "Editor",
    defaultValue: "16",
    acceptedValues: "Number from 6 through 72",
    description: "Sets the editor text size, in points.",
    example: "font-size = 16"
  },
  {
    key: "line-height",
    category: "Editor",
    defaultValue: "25.6",
    acceptedValues: "Number from 8 through 120",
    description: "Sets the height of each line of text, in points.",
    example: "line-height = 25.6"
  },
  {
    key: "content-width",
    category: "Editor",
    defaultValue: "640",
    acceptedValues: "Number from 320 through 2000",
    description: "Sets the centered writing column width used by the timeline.",
    example: "content-width = 640"
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
    description: "Sets how many days stay loaded while scrolling through history.",
    example: "history-window-days = 180"
  },
  {
    key: "autosave-delay",
    category: "Saving",
    defaultValue: "0.55",
    acceptedValues: "Number from 0 through 60",
    description: "Sets how long to wait after typing stops before saving, in seconds.",
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
    defaultValue: "hidden",
    acceptedValues: "hidden (legacy muted is treated as hidden)",
    description: "Hides Markdown punctuation outside the active line. The older muted value uses the same behavior.",
    example: "markdown-marker-visibility = hidden"
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
font-size = 16
line-height = 25.6
content-width = 640
recent-days = 7
history-batch-days = 14
history-window-days = 180
autosave-delay = 0.55
hide-empty-weekends = false
markdown-marker-visibility = hidden

# Split config into another file:
# config-file = extras.current
config-file = ?machine.current`;

export const highlightedSettings = settings.filter((setting) =>
  ["library-root", "font-size", "line-height", "autosave-delay"].includes(setting.key)
);
