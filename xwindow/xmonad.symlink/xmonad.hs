import Control.Monad
import Data.Maybe
import XMonad
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.ManageDocks
import XMonad.Hooks.SetWMName
import XMonad.Actions.CycleWS
import XMonad.Util.EZConfig(additionalKeys)
import XMonad.Util.Run(spawnPipe)
import XMonad.Layout.PerWorkspace
import qualified XMonad.StackSet as W
import qualified Data.List as L (find,filter)
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.WallpaperSetter
import XMonad.Config.Gnome

myManageHook = composeAll
    [ className =? "Tilda"                                   --> doFloat
    , className =? "ignition"                                --> doFloat
    , className =? "Thunderbird"                             --> doShift "2:mail"
    , className =? "jetbrains-clion"                         --> doShift "3:clion"
    , className =? "jetbrains-idea"                          --> doShift "3:clion"
    , className =? "Gvim"                                    --> doShift "4:gvim"
    , title     =? "Ghim, Hojin - Outlook Web App - Vivaldi" --> doShift "8:calendar"
    , title     =? "Google Calendar - Vivaldi"               --> doShift "8:calendar"
    , title     =? "Calendar - hojin@amazon.co.uk — Mozilla Firefox" --> doShift "8:calendar"
    , className =? "yakyak"                                  --> doShift "9:messenger"
    , className =? "AmazonChime"                             --> doShift "9:messenger"
    , title     =? "Amazon Chime — Mozilla Firefox"          --> doShift "9:messenger"
    , title     =? "WhatsApp - Vivaldi"                      --> doShift "9:messenger"
    , className =? "Slack"                                   --> doShift "9:messenger"
    --, className =? "firefox"                                 --> doShift "1:browser"
    ]

-- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#dzen_status_bars
{-main = xmonad =<< xmobar myConfig-}
main = xmonad =<< dzen myConfig
{-main = xmonad =<< dzenWithFlags "-tx 500" myConfig-}

myConfig = gnomeConfig
    { startupHook = composeAll [
        -- https://bbs.archlinux.org/viewtopic.php?pid=744577#p744577
        setWMName "LG3D",
                  -- https://github.com/texttheater/xminid/blob/master/xmonad.hs
        startupHook gnomeConfig,
        fullscreenStartupHook
    ]
    , handleEventHook = composeAll [
        handleEventHook gnomeConfig,
        fullscreenEventHook
    ]
    , modMask = mod4Mask
    -- https://wiki.haskell.org/Xmonad/General_xmonad.hs_config_tips#ManageHook_examples
    , workspaces = myWorkspaces
    -- https://wiki.haskell.org/Xmonad/Config_archive/John_Goerzen's_Configuration#Final_Touches
    -- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#Make_space_for_a_panel_dock_or_tray
    , manageHook = manageDocks <+> myManageHook
                <+> manageHook gnomeConfig
    , layoutHook = avoidStruts  $  layoutHook gnomeConfig
    } `additionalKeys` myKeys

myWorkspaces = ["1:browser", "2:mail", "3:clion", "4:gvim", "5", "6", "7:browser", "8:calendar", "9:messenger"]
{-myWorkspaces = ["1","2","3","4","5","6","7","8","9"]-}

-- https://wiki.haskell.org/Xmonad/Config_archive/John_Goerzen%27s_Configuration#Customizing_xmonad
myKeys = [ ((mod4Mask .|. mod1Mask, xK_l), spawn "gnome-screensaver-command --lock")
    -- https://hackage.haskell.org/package/xmonad-contrib-0.15/docs/XMonad-Actions-CycleWS.html#v:nextScreen
    , ((mod4Mask, xK_quoteleft), nextScreen)
    , ((mod4Mask, xK_0), moveTo Next EmptyWS)  -- find a free workspace
    ] ++
    -- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#Replacing_greedyView_with_view
    [ ((m .|. mod4Mask, k), windows $ f i)
    | (i, k) <- zip myWorkspaces [xK_1 .. xK_9]
    , (f, m) <- [(W.view, 0), (W.shift, shiftMask), (W.greedyView, controlMask), (myGreedyView, mod1Mask)]
    ]

-- TODO let's make it lruView
-- Copied from https://hackage.haskell.org/package/xmonad-0.15/docs/src/XMonad.StackSet.html#greedyView
myGreedyView :: (Eq s, Eq i) => i -> W.StackSet i l a s sd -> W.StackSet i l a s sd
myGreedyView w ws
     | any wTag (W.hidden ws) = W.view w ws
     | (Just s) <- L.find (wTag . W.workspace) (W.visible ws)
                            = ws { W.current = (W.current ws) { W.workspace = W.workspace s }
                                 , W.visible = s { W.workspace = W.workspace (W.current ws) }
                                           : L.filter (not . wTag . W.workspace) (W.visible ws) }
     | otherwise = ws
   where wTag = (w == ) . W.tag

   -- https://github.com/texttheater/xminid/blob/master/xmonad.hs
fullscreenStartupHook :: X ()
fullscreenStartupHook = withDisplay $ \dpy -> do
    r <- asks theRoot
    a <- getAtom "_NET_SUPPORTED"
    c <- getAtom "ATOM"
    f <- getAtom "_NET_WM_STATE_FULLSCREEN"
    io $ do
        sup <- (join . maybeToList) <$> getWindowProperty32 dpy a r
        when (fromIntegral f `notElem` sup) $
            changeProperty32 dpy r a c propModeAppend [fromIntegral f]
