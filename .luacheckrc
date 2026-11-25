-- .luacheckrc for Sprint Bar
std = "lua51"
max_line_length = false
codes = true

-- Globals the addon defines or writes.
globals = {
    "SprintBarDB",
    "SprintBarCharDB",
    "SprintBar_OnAddonCompartmentClick",
    "SlashCmdList",
    "SLASH_SPRINTBAR1",
    "SLASH_SPRINTBAR2",
}

-- WoW globals the addon only reads.
read_globals = {
    "C_AddOns", "C_MountJournal", "C_Timer", "Enum", "Settings", "SOUNDKIT", "UIParent", "UIErrorsFrame",
    "CreateFrame", "hooksecurefunc", "issecretvalue", "InCombatLockdown",
    "GetUnitSpeed", "IsPlayerMoving", "IsMounted", "IsFlying", "IsSwimming",
    "UnitOnTaxi", "UnitInVehicle", "UnitIsDeadOrGhost", "UnitLevel",
    "GetBindingKey", "GetBindingText", "GetBindingAction", "GetBindingName", "SetOverrideBinding", "ClearOverrideBindings",
    "GetBuildInfo", "GetTime", "time", "PlaySound", "ToggleRun",
    "IsAltKeyDown", "IsControlKeyDown", "IsShiftKeyDown", "IsMetaKeyDown",
    "GetConvertedKeyOrButton", "IsKeyPressIgnoredForBinding", "CreateKeyChordStringUsingMetaKeyState",
    "CreateSettingsButtonInitializer", "MinimalSliderWithSteppersMixin",
    "DEFAULT_CHAT_FRAME", "GameFontNormal", "GameFontHighlightSmall",
}
