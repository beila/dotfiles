import Control.Monad
import Data.Maybe
import System.Directory (getHomeDirectory, setCurrentDirectory)
import qualified Data.List as L (find,filter)
import qualified XMonad.StackSet as W
import XMonad
import XMonad.Actions.CycleWS
import XMonad.Config.Gnome
import XMonad.Util.NamedScratchpad
import Graphics.X11.ExtraTypes.XF86
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.ManageDocks
import XMonad.Hooks.ManageHelpers
import XMonad.Hooks.SetWMName
import XMonad.Layout.PerWorkspace
import XMonad.Util.EZConfig(additionalKeys)

-- Scratchpads: two independent floating ghostty terminals
-- End key toggles scratchpad1, PgDn toggles scratchpad2
-- Positioning handled by adaptiveFloat based on screen orientation
myScratchpads = [ NS "ghostty1" "ghostty --x11-instance-name=scratchpad1 --working-directory=$HOME"
                     (appName =? "scratchpad1")
                     (adaptiveFloat True)
                , NS "ghostty2" "ghostty --x11-instance-name=scratchpad2 --working-directory=$HOME"
                     (appName =? "scratchpad2")
                     (adaptiveFloat False) ]

-- Float scratchpad as half the screen, adapting to orientation
adaptiveFloat :: Bool -> ManageHook
adaptiveFloat isFirst = do
    sc <- liftX $ withWindowSet $ return . screenRect . W.screenDetail . W.current
    let Rectangle _ _ sw sh = sc
        rect = if sw > sh
               then if isFirst
                    then W.RationalRect 0.02 0.02 0.47 0.96
                    else W.RationalRect 0.51 0.02 0.47 0.96
               else if isFirst
                    then W.RationalRect 0.02 0.02 0.96 0.47
                    else W.RationalRect 0.02 0.51 0.96 0.47
    doRectFloat rect

-- Custom scratchpad toggle:
-- focused → hide, visible but unfocused → focus, hidden → show on current workspace
scratchpadToggle name = withWindowSet $ \ws -> do
    let query = case filter (\(NS n _ _ _) -> n == name) myScratchpads of
                    (NS _ _ q _:_) -> q
                    _              -> return False
    let isSP w = runQuery query w
    case W.peek ws of
        Just w -> do
            sp <- isSP w
            if sp
                then namedScratchpadAction myScratchpads name
                else do
                    let allVisible = concatMap (W.integrate' . W.stack . W.workspace) (W.current ws : W.visible ws)
                    spWindows <- filterM isSP allVisible
                    case spWindows of
                        (s:_) -> windows $ W.focusWindow s
                        []    -> namedScratchpadAction myScratchpads name
        Nothing -> namedScratchpadAction myScratchpads name

myManageHook = composeAll
    [ appName   =? "Alert"                                           --> doFloat
    , isInProperty "_NET_WM_WINDOW_TYPE" "_NET_WM_WINDOW_TYPE_DESKTOP" --> doLower
    , className =? "Tilda"                                           --> doFloat
    , className =? "ignition"                                        --> doFloat
    , className =? "Evolution-alarm-notify"                          --> doFloat
    , className =? "Gnome-panel"                                     --> doFloat
    , appName   =? "gnome-panel"                                     --> doFloat
    , appName   =? "Mail"                                            --> doShift "2:mail"
    , className =? "thunderbird"                                     --> doShift "2:mail"
    , className =? "evolution.real"                                  --> doShift "2:mail"
    , className =? "jetbrains-clion"                                 --> doShift "3:nvim"
    , className =? "jetbrains-idea"                                  --> doShift "3:nvim"
    , className =? "neovide"                                         --> doShift "3:nvim"
    , className =? "Gvim"                                            --> doShift "3:nvim"
    , title     =? "Ghim, Hojin - Outlook Web App - Vivaldi"         --> doShift "7:calendar"
    , title     =? "Ghim, Hojin - Outlook Web App - Mozilla Firefox" --> doShift "7:calendar"
    , title     =? "Google Calendar - Vivaldi"                       --> doShift "7:calendar"
    , title     =? "Google Calendar - Mozilla Firefox"               --> doShift "7:calendar"
    , title     =? "Calendar - hojin@amazon.co.uk — Mozilla Firefox" --> doShift "7:calendar"
    , title     =? "Email - hojin@amazon.co.uk — Mozilla Firefox"    --> doShift "7:calendar"
    , className =? "AmazonChime"                                     --> doShift "8:meeting"
    , title     =? "Amazon Chime — Mozilla Firefox"                  --> doShift "8:meeting"
    , className =? "zoom"                                            --> doShift "8:meeting"
    , title     =? "zoom_linux_float_video_window"                   --> doFloat
    , title     =? "Meeting chat"                                    --> doShift "8:meeting"
    , className =? "yakyak"                                          --> doShift "9:messenger"
    , title     =? "WhatsApp - Vivaldi"                              --> doShift "9:messenger"
    , title     =? "WhatsApp - Mozilla Firefox"                      --> doShift "9:messenger"
    , title     =? "Gmail - Mozilla Firefox"                         --> doShift "9:messenger"
    , className =? "Slack"                                           --> doShift "9:messenger"
    , className =? "firefox"                                         --> doShift "1:browser"
    , manageHook gnomeConfig
    , manageDocks
    , namedScratchpadManageHook myScratchpads
    ]

-- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#dzen_status_bars
{-main = xmonad =<< xmobar myConfig-}
main = xmonad $ ewmhFullscreen myConfig
{-main = xmonad =<< dzenWithFlags "-tx 500" myConfig-}

myConfig = gnomeConfig
    { terminal = "gnome-terminal"
    , startupHook = composeAll [
        io (getHomeDirectory >>= setCurrentDirectory),
        -- https://bbs.archlinux.org/viewtopic.php?pid=744577#p744577
        setWMName "LG3D",
                  -- https://github.com/texttheater/xminid/blob/master/xmonad.hs
        startupHook gnomeConfig,
        fullscreenStartupHook,
        spawn "pgrep xfce4-panel || xfce4-panel",
        spawn "pgrep albert || albert",
        spawn "pgrep volumeicon || volumeicon",
        -- Reapply xmodmap on keyboard hotplug (GNOME resets keymap on device changes)
        spawn "pgrep inputplug || inputplug -c ~/.dotfiles/xwindow/bin/on-input-change",
        -- Initial xmodmap apply (sleep to let GNOME set its keymap first)
        spawn "sleep 2 && xmodmap ~/.Xmodmap",
        -- xcape: tap Super alone → emit F13 (used to toggle albert)
        -- Super still works as modifier when held with other keys
        spawn "pgrep xcape || xcape -e 'Super_L=XF86Launch1'"
    ]
    , handleEventHook = handleEventHook gnomeConfig
    , modMask = mod4Mask
    -- https://wiki.haskell.org/Xmonad/General_xmonad.hs_config_tips#ManageHook_examples
    , workspaces = myWorkspaces
    -- https://wiki.haskell.org/Xmonad/Config_archive/John_Goerzen's_Configuration#Final_Touches
    -- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#Make_space_for_a_panel_dock_or_tray
    , manageHook = myManageHook
    , layoutHook = avoidStruts $ layoutHook gnomeConfig
    } `additionalKeys` myKeys

myWorkspaces = ["1:browser", "2:mail", "3:nvim", "4", "5", "6", "7:calendar", "8:meeting", "9:messenger"]
{-myWorkspaces = ["1","2","3","4","5","6","7","8","9"]-}

-- https://wiki.haskell.org/Xmonad/Config_archive/John_Goerzen%27s_Configuration#Customizing_xmonad
myKeys = [ ((mod4Mask .|. mod1Mask, xK_l), spawn "gnome-screensaver-command --lock")
    , ((0, xF86XK_Launch1), spawn "albert toggle")  -- triggered by Super tap via xcape
    , ((0, xF86XK_Launch2), scratchpadToggle "ghostty1")   -- End key (remapped in ~/.Xmodmap)
    , ((0, xF86XK_Launch3), scratchpadToggle "ghostty2")  -- PgDn key (remapped in ~/.Xmodmap)
    , ((0, xF86XK_AudioRaiseVolume), spawn "$HOME/.dotfiles/xwindow/bin/volume-osd up")
    , ((0, xF86XK_AudioLowerVolume), spawn "$HOME/.dotfiles/xwindow/bin/volume-osd down")
    , ((0, xF86XK_AudioMute), spawn "$HOME/.dotfiles/xwindow/bin/volume-osd toggle")
    , ((mod4Mask, xF86XK_AudioRaiseVolume), spawn "$HOME/.dotfiles/xwindow/bin/cycle-audio-output")
    , ((mod4Mask, xF86XK_AudioLowerVolume), spawn "$HOME/.dotfiles/xwindow/bin/cycle-audio-input")
    -- https://hackage.haskell.org/package/xmonad-contrib-0.15/docs/XMonad-Actions-CycleWS.html#v:nextScreen
    , ((mod4Mask, xK_quoteleft), nextScreen)
    , ((mod4Mask, xK_equal), nextScreen)
    , ((mod4Mask, xK_0), moveTo Next emptyWS)  -- find a free workspace
    ] ++
    -- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#Replacing_greedyView_with_view
    [ ((m .|. mod4Mask, k), windows $ f i)
    | (i, k) <- zip myWorkspaces [xK_1 .. xK_9]
    , (f, m) <- [(W.view, 0), (W.shift, shiftMask), (W.greedyView, controlMask), (myGreedyView, mod2Mask)]
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
