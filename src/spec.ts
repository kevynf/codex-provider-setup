export interface ModelPreset {
  readonly model: string;
  readonly reasoningEffort: string;
  readonly contextWindow: number;
}

export interface TypeStyle {
  readonly marker: string;
  readonly powershellColor: string;
  readonly ansiColor: number;
}

export interface SetupSpec {
  readonly version: string;
  readonly modelPresets: readonly ModelPreset[];
  readonly messages: Readonly<Record<string, string>>;
  readonly typeStyles: Readonly<Record<string, TypeStyle>>;
}

export const setupSpec = {
  version: "1.0.0",
  modelPresets: [
    { model: "gpt-6-sol", reasoningEffort: "medium", contextWindow: 272000 },
    { model: "gpt-6-astra", reasoningEffort: "low", contextWindow: 272000 },
    { model: "gpt-6-luna", reasoningEffort: "medium", contextWindow: 272000 },
    { model: "gpt-5.6-sol", reasoningEffort: "medium", contextWindow: 272000 },
  ],
  messages: {
    AppTitle: "Codex Provider Setup  v{0}",
    CodexHome: "Codex home: {0}",
    SetupModeTitle: "Choose a setup mode",
    ModelPresetsAction: "Model presets",
    ManualSetupAction: "Manual setup",
    RestoreAction: "Restore",
    SelectOption: "Select an option",
    InputUnavailable: "Unable to read input; the current host may not be interactive.",
    InvalidInput: "Invalid input. Enter one of: {0}.",
    InvalidInputLimit: "No valid input after three attempts. No files were changed.",
    ValueRequired: "This value cannot be empty.",
    ValueLimit: "No value entered after three attempts. No files were changed.",
    ApiKeyPrompt: "Enter API key",
    ApiKeyUnavailable: "Unable to read the API key; the current host may not be interactive.",
    ApiKeyLineBreaks: "The API key cannot contain line breaks.",
    ApiKeyRequired: "The API key cannot be empty.",
    ApiKeyLimit: "No API key entered after three attempts. No files were changed.",
    BaseUrlRequired: "The Base URL cannot be empty.",
    BaseUrlExpanded: "Expanded Base URL: {0}",
    BaseUrlInvalid: "Invalid Base URL: {0}",
    BaseUrlScheme: "Only http and https Base URLs are supported.",
    BaseUrlCredentials: "The Base URL cannot contain a username or password.",
    ModelMenuTitle: "Select an OpenAI model",
    DefaultMarker: "default, ",
    ModelPresetFormat: "{0} ({1}reasoning: {2})",
    ManualModelOption: "Enter a model ID without capability settings",
    ModelInputMessage: "Specify the model ID.",
    ModelPrompt: "Model ID",
    BaseUrlInputTitle: "Base URL",
    DefaultField: "Default",
    DefaultBaseUrlPrompt: "Enter Base URL or press Enter to use the default",
    ProviderInputMessage: "Specify the provider display name.",
    ProviderPrompt: "Provider display name",
    BaseUrlInputMessage: "Specify the provider Base URL.",
    BaseUrlPrompt: "Base URL",
    RemovedSection: "Removed old {0}; it will be rewritten for the current selection",
    RemovedProfile: "Removed {0} because profile overrides the selected model",
    RewroteSetting: "Rewrote top-level setting: {0}",
    DuplicateSetting: "Generated config.toml contains a duplicate top-level key: {0}",
    MissingSetting: "Generated config.toml is missing the top-level key: {0}",
    ProviderSectionCount: "Generated config.toml must contain exactly one [model_providers.{0}] section.",
    BackupIncomplete: "The backup is incomplete. Missing: {0}",
    BackupManifestInvalid: "The backup manifest does not specify whether the original config.toml existed.",
    BackupDamaged: "The backup is damaged. Missing: {0}",
    ExistingManagedProvider:
      "The existing config already contains [model_providers.{0}], but no script backup exists. Setup was stopped to avoid overwriting it.",
    ConfigSummaryTitle: "Configuration summary",
    ProviderField: "Provider",
    BaseUrlField: "Base URL",
    ModelField: "Model",
    ReasoningField: "Reasoning effort",
    ContextField: "Context window",
    ApiKeyWarning:
      "The API key will be stored as plain text in config.toml. It will not be shown in the terminal or manifest.",
    GeneratedConfigInvalid: "Generated config.toml failed validation. The original file was not changed. {0}",
    ConfigWriteFailed: "Failed to write the config. The pre-setup backup remains at {0}. {1}",
    ConfigUpdated: "Updated {0}",
    ConfigChangesTitle: "Configuration changes",
    ConfigCompleteTitle: "Configuration complete",
    RestartCodex: "Restart Codex CLI.",
    ConfirmModel: "After restarting, confirm that model is {0}.",
    RestoreTitle: "Restore the pre-setup Codex config",
    RestoreWarning: "Restore will overwrite all manual changes made to config.toml after setup.",
    RestoreChoiceTitle: "Choose a restore action",
    RestoreConfirmAction: "Restore configuration",
    CancelAction: "Cancel",
    BackupUnavailable: "No backup is available.",
    RestoreCanceled: "Canceled. No files were changed.",
    ConfigRestored: "Restored config.toml.",
    ConfigDeleted: "Deleted the config.toml created by this script.",
    ConfigAlreadyAbsent: "The generated config.toml was already absent.",
    BackupRemoved: "Removed the backup directory.",
    RestoreCompleteTitle: "Restore complete",
    CodexHomeMissing: "Codex config directory not found: {0}. Run Codex CLI once or set CODEX_HOME, then try again.",
  },
  typeStyles: {
    Title: { marker: "", powershellColor: "Cyan", ansiColor: 36 },
    Ordered: { marker: "", powershellColor: "Cyan", ansiColor: 36 },
    Info: { marker: "i", powershellColor: "Cyan", ansiColor: 36 },
    Detail: { marker: "i", powershellColor: "DarkGray", ansiColor: 90 },
    Success: { marker: "+", powershellColor: "Green", ansiColor: 32 },
    Warning: { marker: "!", powershellColor: "Yellow", ansiColor: 33 },
    Error: { marker: "X", powershellColor: "Red", ansiColor: 31 },
    Prompt: { marker: "?", powershellColor: "Cyan", ansiColor: 36 },
    Change: { marker: "~", powershellColor: "Cyan", ansiColor: 36 },
  },
} as const satisfies SetupSpec;
