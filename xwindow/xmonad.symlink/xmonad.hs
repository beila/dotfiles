import XMonad
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.ManageDocks
import XMonad.Hooks.SetWMName
import XMonad.Actions.CycleWS
import XMonad.Util.EZConfig(additionalKeys)
import XMonad.Util.Run(spawnPipe)
import XMonad.Layout.PerWorkspace
import qualified XMonad.StackSet as W

myManageHook = composeAll
    [ className =? "Tilda"  --> doFloat
    , className =? "Thunderbird" --> doShift "1:mail"
    , className =? "jetbrains-clion" --> doShift "3:clion"
    , className =? "yakyak" --> doShift "9:messenger"
    , className =? "AmazonChime" --> doShift "9:messenger"
    , className =? "Gvim" --> doShift "4:gvim"
    ]

-- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#dzen_status_bars
main = xmonad =<< dzen myConfig

myConfig = defaultConfig
	-- https://bbs.archlinux.org/viewtopic.php?pid=744577#p744577
	{ startupHook = setWMName "LG3D"
    , modMask = mod4Mask
    -- https://wiki.haskell.org/Xmonad/General_xmonad.hs_config_tips#ManageHook_examples
    , workspaces = myWorkspaces
    -- https://wiki.haskell.org/Xmonad/Config_archive/John_Goerzen's_Configuration#Final_Touches
	-- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#Make_space_for_a_panel_dock_or_tray
	, manageHook = manageDocks <+> myManageHook
                <+> manageHook defaultConfig
	, layoutHook = avoidStruts  $  layoutHook defaultConfig
	} `additionalKeys` myKeys

myWorkspaces = ["1:mail", "2:work browser", "3:clion", "4:gvim", "5", "6", "7:browser", "8:calendar", "9:messenger"]
{-myWorkspaces = ["1","2","3","4","5","6","7","8","9"]-}

-- https://wiki.haskell.org/Xmonad/Config_archive/John_Goerzen%27s_Configuration#Customizing_xmonad
myKeys = [ ((mod4Mask .|. mod1Mask, xK_l), spawn "gnome-screensaver-command --lock")
    -- https://hackage.haskell.org/package/xmonad-contrib-0.15/docs/XMonad-Actions-CycleWS.html#v:nextScreen
    , ((mod4Mask, xK_w), nextScreen)
    , ((mod4Mask, xK_0), moveTo Next EmptyWS)  -- find a free workspace
    ] ++
    -- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#Replacing_greedyView_with_view
    [ ((m .|. mod4Mask, k), windows $ f i)
    | (i, k) <- zip myWorkspaces [xK_1 .. xK_9]
    , (f, m) <- [(W.view, 0), (W.shift, shiftMask), (W.greedyView, controlMask)]
    ]
