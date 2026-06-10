Config = {}

-- Only runs while this is true. Toggle with the keybind below.
Config.EnabledByDefault = true

-- Keybind used to toggle the inspector on/off.
Config.ToggleCommand = 'togglepropinspect'
Config.ToggleKey = 'F7'

-- This script only inspects while the player is holding this weapon.
Config.RequiredWeapon = `WEAPON_PISTOL`

-- You must be aiming/free-aiming with the pistol for the inspector to run.
Config.RequireAiming = true

-- Raycast distance from gameplay camera.
Config.MaxDistance = 80.0

-- How often to inspect while aiming. Lower = faster, higher = lighter.
Config.ScanIntervalMs = 100

-- Entity types to fully inspect.
-- 1 = peds, 2 = vehicles/trains/trailers, 3 = objects/props.
-- Do NOT add [0] here. Type 0 is a world/collision pseudo-hit and some entity natives can crash on it.
Config.AllowedEntityTypes = {
    [1] = true,
    [2] = true,
    [3] = true,
}

-- Type 0/name-only mode.
-- This tries to read only the archetype/model name from type 0 hits, without doing normal entity inspection.
-- Useful for some map/world props where the raycast returns type 0 but GetEntityArchetypeName still gives a name.
Config.Type0NameOnly = true

-- Show a small status message when the pistol is held but nothing valid is hit.
Config.ShowNoHitStatus = true

-- Display options.
Config.DrawOnScreen = true

-- On-screen debug panel position.
-- Increase X to move it right if your HUD/crop cuts off the left edge.
Config.ScreenTextX = 0.055
Config.ScreenTextY = 0.72
Config.DrawOnEntity = true
Config.PrintOnChange = true

-- Marker line from camera hit point. Handy for confirming exact target.
Config.DrawDebugLine = true

-- Control to print the current hit to F8.
-- 38 = E by default.
Config.PrintControl = 38

-- When true, unknown object hashes are printed once so you can add them to prop_names.lua later.
Config.LogUnknownProps = true


-- When you press E, also list nearby real entities around the hit point.
-- This helps when the raycast hits an invisible collision shell, type 0 world hit,
-- or vehicle/train entity instead of the actual prop placement you are trying to identify.
Config.PrintNearbyObjects = true
Config.NearbyRadius = 7.0
Config.MaxNearbyObjects = 15
