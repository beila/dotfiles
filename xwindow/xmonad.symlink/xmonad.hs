import XMonad
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.ManageDocks
import XMonad.Hooks.SetWMName
import XMonad.Actions.Plane

myManageHook = composeAll
    [ className =? "Tilda"  --> doFloat
    ]

-- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#dzen_status_bars
main = xmonad =<< dzen myConfig

myConfig = defaultConfig
	-- https://bbs.archlinux.org/viewtopic.php?pid=744577#p744577
	{ startupHook = setWMName "LG3D"
    , modMask = mod4Mask
    -- https://wiki.haskell.org/Xmonad/Config_archive/John_Goerzen's_Configuration#Final_Touches
	-- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#Make_space_for_a_panel_dock_or_tray
	, manageHook = manageDocks <+> myManageHook
                <+> manageHook defaultConfig
	, layoutHook = avoidStruts  $  layoutHook defaultConfig
	}
