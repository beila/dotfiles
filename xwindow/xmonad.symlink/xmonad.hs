import Control.Monad
import Data.Maybe
import Data.Monoid (All(..))
import System.Directory (getHomeDirectory, setCurrentDirectory)
import qualified Data.List as L (find,filter)
import qualified Data.Map as M (member)
import qualified XMonad.StackSet as W
import XMonad
import XMonad.Actions.CycleWS
import XMonad.Config.Gnome
import XMonad.Util.NamedScratchpad
import Graphics.X11.ExtraTypes.XF86
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.ManageDocks
import XMonad.Actions.CopyWindow
import XMonad.Hooks.InsertPosition
import XMonad.Hooks.ManageHelpers
import XMonad.Hooks.SetWMName
import XMonad.Hooks.Rescreen
import XMonad.Layout.PerWorkspace
import XMonad.Util.EZConfig(additionalKeys)

-- Scratchpads: two independent floating ghostty terminals
-- End key toggles scratchpad1, PgDn toggles scratchpad2
-- Positioning handled by adaptiveFloat based on screen orientation
myScratchpads = [ NS "ghostty1" "ghostty --x11-instance-name=scratchpad1 --working-directory=$HOME -e $HOME/.dotfiles/bin/zellij-cycle scratch1"
                     (appName =? "scratchpad1")
                     (adaptiveFloat True)
                , NS "ghostty2" "ghostty --x11-instance-name=scratchpad2 --working-directory=$HOME -e $HOME/.dotfiles/bin/zellij-cycle scratch2"
                     (appName =? "scratchpad2")
                     (adaptiveFloat False) ]

-- Float scratchpad as half the screen, adapting to orientation
adaptiveFloat :: Bool -> ManageHook
adaptiveFloat isFirst = do
    sc <- liftX $ withWindowSet $ return . screenRect . W.screenDetail . W.current
    let Rectangle _ _ sw sh = sc
        rect = if sw > sh
               then if isFirst
                    then W.RationalRect 0.01 0.03 0.485 0.94
                    else W.RationalRect 0.505 0.03 0.485 0.94
               else if isFirst
                    then W.RationalRect 0.01 0.03 0.98 0.475
                    else W.RationalRect 0.01 0.505 0.98 0.475
    doRectFloat rect

-- Scratchpad toggle (each scratchpad independent):
-- 1. Focused on current screen → hide (move to NSP)
-- 2. Visible on another screen → just focus it
-- 3. Hidden (NSP or any non-visible workspace) → move to current workspace, float, and focus
scratchpadToggle name = withWindowSet $ \ws -> do
    let query = case filter (\(NS n _ _ _) -> n == name) myScratchpads of
                    (NS _ _ q _:_) -> q
                    _              -> return False
    let isSP w = runQuery query w
    let isFirst = name == "ghostty1"
    let allWins = W.allWindows ws
    spWins <- filterM isSP allWins
    case spWins of
        [] -> namedScratchpadAction myScratchpads name  -- not spawned yet
        (s:_) -> do
            isFocused <- case W.peek ws of
                Just w  -> isSP w
                Nothing -> return False
            let visibleWins = concatMap (W.integrate' . W.stack . W.workspace) (W.current ws : W.visible ws)
            let isVisible = s `elem` visibleWins
            if isFocused
                then namedScratchpadAction myScratchpads name  -- hide (no refloat!)
                else do
                    if isVisible
                        then windows $ W.focusWindow s  -- on another screen, just focus
                        else namedScratchpadAction myScratchpads name  -- bring from hidden
                    -- Refloat for both visible and hidden cases to adapt to screen orientation.
                    -- Do NOT refloat on hide — it would bring the scratchpad back.
                    refloatScratchpad isFirst isSP

-- Find the scratchpad window and refloat it
refloatScratchpad :: Bool -> (Window -> X Bool) -> X ()
refloatScratchpad isFirst isSP = withWindowSet $ \ws -> do
    let allWins = concatMap (W.integrate' . W.stack . W.workspace) (W.current ws : W.visible ws)
    spWins <- filterM isSP allWins
    case spWins of
        (s:_) -> refloatAdaptive isFirst s
        []    -> return ()

-- Reposition a window using adaptiveFloat on the current screen
refloatAdaptive :: Bool -> Window -> X ()
refloatAdaptive isFirst w = do
    sc <- withWindowSet $ return . screenRect . W.screenDetail . W.current
    let Rectangle _ _ sw sh = sc
        rect = if sw > sh
               then if isFirst
                    then W.RationalRect 0.01 0.03 0.485 0.94
                    else W.RationalRect 0.505 0.03 0.485 0.94
               else if isFirst
                    then W.RationalRect 0.01 0.03 0.98 0.475
                    else W.RationalRect 0.01 0.505 0.98 0.475
    windows $ W.float w rect

-- Copy the managed window (not the focused one) to all workspaces
copyToAllHook :: ManageHook
copyToAllHook = ask >>= \w -> doF (\s -> foldr (copyWindow w . W.tag) s (W.workspaces s))

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
    , className =? "zoom" <&&> title /=? "zoom_linux_float_message_reminder" --> doShift "8:meeting"
    , title     =? "zoom_linux_float_message_reminder"   --> doFloat <> copyToAllHook <> insertPosition Below Older
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
main = xmonad $ ewmhFullscreen $ rescreenHook rescreenCfg myConfig
{-main = xmonad =<< dzenWithFlags "-tx 500" myConfig-}

-- After monitor hotplug, swap NSP off any visible screen
rescreenCfg = def { afterRescreenHook = fixNSP }
fixNSP = withWindowSet $ \ws -> do
    let visibleTags = map (W.tag . W.workspace) (W.current ws : W.visible ws)
    when ("NSP" `elem` visibleTags) $
        case filter ((/= "NSP") . W.tag) (W.hidden ws) of
            (w:_) -> windows $ W.greedyView (W.tag w)
            []    -> return ()

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
        spawn "pgrep albert || albert"
    ]
    , handleEventHook = handleEventHook gnomeConfig <> rescueOffscreenHook
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
    , ((0, xF86XK_Launch1), spawn "albert toggle")  -- Super tap via keyd (prog1)
    , ((0, xF86XK_Launch2), scratchpadToggle "ghostty1")   -- Alt_L tap via keyd (prog2)
    , ((0, xF86XK_Launch3), scratchpadToggle "ghostty2")  -- Alt_R tap via keyd (prog3)
    , ((0, xF86XK_AudioRaiseVolume), spawn "$HOME/.dotfiles/xwindow/bin/volume-osd up")
    , ((0, xF86XK_AudioLowerVolume), spawn "$HOME/.dotfiles/xwindow/bin/volume-osd down")
    , ((0, xF86XK_AudioMute), spawn "$HOME/.dotfiles/xwindow/bin/volume-osd toggle")
    , ((0, xF86XK_MonBrightnessUp), spawn "$HOME/.dotfiles/xwindow/bin/brightness-osd up")
    , ((0, xF86XK_MonBrightnessDown), spawn "$HOME/.dotfiles/xwindow/bin/brightness-osd down")
    , ((mod4Mask, xF86XK_AudioRaiseVolume), spawn "$HOME/.dotfiles/xwindow/bin/cycle-audio-output")
    , ((mod4Mask, xF86XK_AudioLowerVolume), spawn "$HOME/.dotfiles/xwindow/bin/cycle-audio-input")
    -- https://hackage.haskell.org/package/xmonad-contrib-0.15/docs/XMonad-Actions-CycleWS.html#v:nextScreen
    , ((mod4Mask, xK_quoteleft), nextScreen)
    , ((mod4Mask, xK_equal), nextScreen)
    , ((mod4Mask, xK_0), moveTo Next (emptyWS :&: Not (WSIs $ return (\w -> W.tag w == "NSP"))))  -- find a free workspace (skip NSP)
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

-- Rescue windows that move themselves offscreen (e.g. Zoom bug)
rescueOffscreenHook :: Event -> X All
rescueOffscreenHook ConfigureEvent{ev_window = w, ev_x = ex, ev_y = ey, ev_width = ew, ev_height = eh} = do
    when (ew > 100 && eh > 100) $ do  -- ignore tiny windows (trays, etc.)
        screens <- withWindowSet $ return . W.screens
        let rects = map (screenRect . W.screenDetail) screens
            totalRight  = maximum $ map (\r -> fromIntegral (rect_x r) + fromIntegral (rect_width r)) rects
            totalBottom = maximum $ map (\r -> fromIntegral (rect_y r) + fromIntegral (rect_height r)) rects
            x = fromIntegral ex :: Int
            y = fromIntegral ey :: Int
        when (x > totalRight || y > totalBottom || x < -500 || y < -500) $
            withWindowSet $ \ws ->
                when (M.member w (W.floating ws)) $ do
                    let sc = screenRect . W.screenDetail . W.current $ ws
                    windows $ W.float w (W.RationalRect 0.1 0.1 0.5 0.5)
    return (All True)
rescueOffscreenHook _ = return (All True)
fullscreenStartupHook = withDisplay $ \dpy -> do
    r <- asks theRoot
    a <- getAtom "_NET_SUPPORTED"
    c <- getAtom "ATOM"
    f <- getAtom "_NET_WM_STATE_FULLSCREEN"
    io $ do
        sup <- (join . maybeToList) <$> getWindowProperty32 dpy a r
        when (fromIntegral f `notElem` sup) $
            changeProperty32 dpy r a c propModeAppend [fromIntegral f]
