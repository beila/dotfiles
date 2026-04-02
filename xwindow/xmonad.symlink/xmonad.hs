import Control.Monad
import qualified Data.List as L (filter, find)
import qualified Data.Map as M (member)
import Data.Maybe
import Data.Monoid (All (..))
import System.Directory (getHomeDirectory, setCurrentDirectory)
import qualified XMonad.StackSet as W

import XMonad
import XMonad.Actions.CopyWindow
import XMonad.Actions.CycleWS
import XMonad.Config.Gnome
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.InsertPosition
import XMonad.Hooks.ManageDocks
import XMonad.Hooks.ManageHelpers
import XMonad.Hooks.Rescreen
import XMonad.Hooks.SetWMName
import XMonad.Util.EZConfig (additionalKeys)
import XMonad.Util.NamedScratchpad

import Graphics.X11.ExtraTypes.XF86

------------------------------------------------------------------------
-- Main
------------------------------------------------------------------------

main = xmonad $ ewmhFullscreen $ rescreenHook monitorHotplugCfg myConfig

myConfig =
    gnomeConfig
        { terminal = "gnome-terminal"
        , startupHook =
            composeAll
                [ io (getHomeDirectory >>= setCurrentDirectory)
                , -- https://bbs.archlinux.org/viewtopic.php?pid=744577#p744577
                  setWMName "LG3D"
                , -- https://github.com/texttheater/xminid/blob/master/xmonad.hs
                  startupHook gnomeConfig
                , fullscreenStartupHook
                , spawn "pgrep xfce4-panel || xfce4-panel"
                , spawn "pgrep albert || albert"
                ]
        , handleEventHook = handleEventHook gnomeConfig <> rescueOffscreenHook
        , logHook = followToCurrentWorkspace (title =? "zoom_linux_float_video_window")
        , modMask = mod4Mask
        , -- https://wiki.haskell.org/Xmonad/General_xmonad.hs_config_tips#ManageHook_examples
          workspaces = myWorkspaces
        , -- https://wiki.haskell.org/Xmonad/Config_archive/John_Goerzen's_Configuration#Final_Touches
          -- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#Make_space_for_a_panel_dock_or_tray
          manageHook = myManageHook
        , layoutHook = avoidStruts $ layoutHook gnomeConfig
        }
        `additionalKeys` myKeys

myWorkspaces = ["1:browser", "2:mail", "3:nvim", "4", "5", "6", "7:calendar", "8:meeting", "9:messenger"]

------------------------------------------------------------------------
-- Scratchpads
------------------------------------------------------------------------

-- Two independent floating ghostty terminals
-- Positioning handled by adaptiveFloat based on screen orientation
myScratchpads =
    [ NS
        "ghostty1"
        "ghostty --x11-instance-name=scratchpad1 --working-directory=$HOME -e $HOME/.dotfiles/bin/zellij-cycle scratch1"
        (appName =? "scratchpad1")
        (adaptiveFloat True)
    , NS
        "ghostty2"
        "ghostty --x11-instance-name=scratchpad2 --working-directory=$HOME -e $HOME/.dotfiles/bin/zellij-cycle scratch2"
        (appName =? "scratchpad2")
        (adaptiveFloat False)
    ]

-- Compute half-screen rect based on screen orientation
scratchpadRect :: Bool -> Rectangle -> W.RationalRect
scratchpadRect isLeftOrTop (Rectangle _ _ sw sh)
    | sw > sh =
        if isLeftOrTop
            then W.RationalRect 0.01 0.03 0.485 0.94
            else W.RationalRect 0.505 0.03 0.485 0.94
    | otherwise =
        if isLeftOrTop
            then W.RationalRect 0.01 0.03 0.98 0.475
            else W.RationalRect 0.01 0.505 0.98 0.475

-- Float scratchpad as half the screen, adapting to orientation
adaptiveFloat :: Bool -> ManageHook
adaptiveFloat isLeftOrTop = do
    sc <- liftX $ withWindowSet $ return . screenRect . W.screenDetail . W.current
    doRectFloat (scratchpadRect isLeftOrTop sc)

-- Scratchpad toggle (each scratchpad independent):
-- 1. Focused on current screen → hide (move to NSP)
-- 2. Visible on another screen → just focus it
-- 3. Hidden (NSP or any non-visible workspace) → move to current workspace, float, and focus
scratchpadToggle name = withWindowSet $ \ws -> do
    let query = case filter (\(NS n _ _ _) -> n == name) myScratchpads of
            (NS _ _ q _ : _) -> q
            _ -> return False
    let isSP = runQuery query
    let isLeftOrTop = name == "ghostty1"
    let allWins = W.allWindows ws
    spWins <- filterM isSP allWins
    case spWins of
        [] -> namedScratchpadAction myScratchpads name -- not spawned yet
        (s : _) -> do
            isFocused <- case W.peek ws of
                Just w -> isSP w
                Nothing -> return False
            let visibleWins = concatMap (W.integrate' . W.stack . W.workspace) (W.current ws : W.visible ws)
            let isVisible = s `elem` visibleWins
            if isFocused
                then namedScratchpadAction myScratchpads name -- hide (no refloat!)
                else do
                    if isVisible
                        then windows $ W.focusWindow s -- on another screen, just focus
                        else namedScratchpadAction myScratchpads name -- bring from hidden
                        -- Refloat for both visible and hidden cases to adapt to screen orientation.
                        -- Do NOT refloat on hide — it would bring the scratchpad back.
                    refloatScratchpad isLeftOrTop isSP

-- Find the scratchpad window and refloat it
refloatScratchpad :: Bool -> (Window -> X Bool) -> X ()
refloatScratchpad isLeftOrTop isSP = withWindowSet $ \ws -> do
    let allWins = concatMap (W.integrate' . W.stack . W.workspace) (W.current ws : W.visible ws)
    spWins <- filterM isSP allWins
    case spWins of
        (s : _) -> do
            sc <- withWindowSet $ return . screenRect . W.screenDetail . W.current
            windows $ W.float s (scratchpadRect isLeftOrTop sc)
        [] -> return ()

------------------------------------------------------------------------
-- Window rules
------------------------------------------------------------------------

-- Copy the managed window (not the focused one) to all workspaces
copyToAllHook :: ManageHook
copyToAllHook = ask >>= \w -> doF (\s -> foldr (copyWindow w . W.tag) s (W.workspaces s))

-- Shift all matching queries to a workspace
shiftAllTo :: WorkspaceId -> [Query Bool] -> ManageHook
shiftAllTo ws = composeAll . map (--> doShift ws)

myManageHook =
    composeAll
        [ floatRules
        , browserRules
        , mailRules
        , editorRules
        , calendarRules
        , meetingRules
        , messengerRules
        , manageHook gnomeConfig
        , manageDocks
        , namedScratchpadManageHook myScratchpads
        ]

floatRules =
    composeAll
        [ appName =? "Alert" --> doFloat
        , isInProperty "_NET_WM_WINDOW_TYPE" "_NET_WM_WINDOW_TYPE_DESKTOP" --> doLower
        , className =? "Tilda" --> doFloat
        , className =? "ignition" --> doFloat
        , className =? "Evolution-alarm-notify" --> doFloat
        , className =? "Gnome-panel" --> doFloat
        , appName =? "gnome-panel" --> doFloat
        ]

browserRules = shiftAllTo "1:browser" [className =? "firefox"]

mailRules = shiftAllTo "2:mail" [appName =? "Mail", className =? "thunderbird", className =? "evolution.real"]

editorRules = shiftAllTo "3:nvim" [className =? "jetbrains-clion", className =? "jetbrains-idea", className =? "neovide", className =? "Gvim"]

calendarRules =
    shiftAllTo
        "7:calendar"
        [ title =? "Ghim, Hojin - Outlook Web App - Vivaldi"
        , title =? "Ghim, Hojin - Outlook Web App - Mozilla Firefox"
        , title =? "Google Calendar - Vivaldi"
        , title =? "Google Calendar - Mozilla Firefox"
        , title =? "Calendar - hojin@amazon.co.uk — Mozilla Firefox"
        , title =? "Email - hojin@amazon.co.uk — Mozilla Firefox"
        ]

meetingRules =
    composeAll
        [ shiftAllTo
            "8:meeting"
            [ className =? "AmazonChime"
            , title =? "Amazon Chime — Mozilla Firefox"
            , className =? "zoom" <&&> title /=? "zoom_linux_float_message_reminder" <&&> title /=? "zoom_linux_float_video_window"
            , title =? "Meeting chat"
            ]
        , title =? "zoom_linux_float_message_reminder" --> doFloat <> copyToAllHook <> insertPosition Below Older
        , title =? "zoom_linux_float_video_window" --> doFloat
        ]

messengerRules =
    shiftAllTo
        "9:messenger"
        [ className =? "yakyak"
        , title =? "WhatsApp - Vivaldi"
        , title =? "WhatsApp - Mozilla Firefox"
        , title =? "Gmail - Mozilla Firefox"
        , className =? "Slack"
        ]

-- Move matching windows to the currently focused workspace
followToCurrentWorkspace :: Query Bool -> X ()
followToCurrentWorkspace q = withWindowSet $ \ws -> do
    let cur = W.tag . W.workspace . W.current $ ws
    wins <- filterM (runQuery q) (W.allWindows ws)
    forM_ wins $ \w -> do
        let onCur = w `elem` concatMap (W.integrate' . W.stack) [W.workspace (W.current ws)]
        unless onCur $ windows $ W.shiftWin cur w

------------------------------------------------------------------------
-- Monitor hotplug
------------------------------------------------------------------------

-- After monitor hotplug, swap NSP off any visible screen
monitorHotplugCfg = def{afterRescreenHook = hideNSPWorkspace}
hideNSPWorkspace = withWindowSet $ \ws -> do
    let visibleTags = map (W.tag . W.workspace) (W.current ws : W.visible ws)
    when ("NSP" `elem` visibleTags) $
        case filter ((/= "NSP") . W.tag) (W.hidden ws) of
            (w : _) -> windows $ W.greedyView (W.tag w)
            [] -> return ()

------------------------------------------------------------------------
-- Key bindings
------------------------------------------------------------------------

-- https://wiki.haskell.org/Xmonad/Config_archive/John_Goerzen%27s_Configuration#Customizing_xmonad
myKeys =
    [ ((mod4Mask .|. mod1Mask, xK_l), spawn "gnome-screensaver-command --lock")
    , ((0, xF86XK_Launch1), spawn "albert toggle") -- Super tap via keyd (prog1)
    , ((0, xF86XK_Launch2), scratchpadToggle "ghostty1") -- Alt_L tap via keyd (prog2)
    , ((0, xF86XK_Launch3), scratchpadToggle "ghostty2") -- Alt_R tap via keyd (prog3)
    , ((0, xF86XK_AudioRaiseVolume), spawn "$HOME/.dotfiles/xwindow/bin/volume-osd up")
    , ((0, xF86XK_AudioLowerVolume), spawn "$HOME/.dotfiles/xwindow/bin/volume-osd down")
    , ((0, xF86XK_AudioMute), spawn "$HOME/.dotfiles/xwindow/bin/volume-osd toggle")
    , ((0, xF86XK_MonBrightnessUp), spawn "$HOME/.dotfiles/xwindow/bin/brightness-osd up")
    , ((0, xF86XK_MonBrightnessDown), spawn "$HOME/.dotfiles/xwindow/bin/brightness-osd down")
    , ((mod4Mask, xF86XK_AudioRaiseVolume), spawn "$HOME/.dotfiles/xwindow/bin/cycle-audio-output")
    , ((mod4Mask, xF86XK_AudioLowerVolume), spawn "$HOME/.dotfiles/xwindow/bin/cycle-audio-input")
    , -- https://hackage.haskell.org/package/xmonad-contrib-0.15/docs/XMonad-Actions-CycleWS.html#v:nextScreen
      ((mod4Mask, xK_quoteleft), nextScreen)
    , ((mod4Mask, xK_equal), nextScreen)
    , ((mod4Mask, xK_0), moveTo Next (emptyWS :&: Not (WSIs $ return (\w -> W.tag w == "NSP")))) -- find a free workspace (skip NSP)
    ]
        ++
        -- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#Replacing_greedyView_with_view
        [ ((m .|. mod4Mask, k), windows $ f i)
        | (i, k) <- zip myWorkspaces [xK_1 .. xK_9]
        , (f, m) <- [(W.view, 0), (W.shift, shiftMask), (W.greedyView, controlMask), (greedyViewNoSwap, mod2Mask)]
        ]

------------------------------------------------------------------------
-- Workspace switching
------------------------------------------------------------------------

-- TODO: make this lruView
-- Copied from https://hackage.haskell.org/package/xmonad-0.15/docs/src/XMonad.StackSet.html#greedyView
greedyViewNoSwap :: (Eq s, Eq i) => i -> W.StackSet i l a s sd -> W.StackSet i l a s sd
greedyViewNoSwap w ws
    | any wTag (W.hidden ws) = W.view w ws
    | (Just s) <- L.find (wTag . W.workspace) (W.visible ws) =
        ws
            { W.current = (W.current ws){W.workspace = W.workspace s}
            , W.visible =
                s{W.workspace = W.workspace (W.current ws)}
                    : L.filter (not . wTag . W.workspace) (W.visible ws)
            }
    | otherwise = ws
  where
    wTag = (w ==) . W.tag

------------------------------------------------------------------------
-- Rescue offscreen windows (e.g. Zoom moving itself to x=12984)
------------------------------------------------------------------------

rescueOffscreenHook :: Event -> X All
rescueOffscreenHook ConfigureEvent{ev_window = w, ev_x = ex, ev_y = ey, ev_width = ew, ev_height = eh} = do
    when (ew > 100 && eh > 100) $ do
        -- ignore tiny windows (trays, etc.)
        screens <- withWindowSet $ return . W.screens
        let rects = map (screenRect . W.screenDetail) screens
            totalRight = maximum $ map (\r -> fromIntegral (rect_x r) + fromIntegral (rect_width r)) rects
            totalBottom = maximum $ map (\r -> fromIntegral (rect_y r) + fromIntegral (rect_height r)) rects
            x = fromIntegral ex :: Int
            y = fromIntegral ey :: Int
        when (x > totalRight || y > totalBottom || x < -500 || y < -500) $
            withWindowSet $ \ws ->
                when (M.member w (W.floating ws)) $
                    windows $
                        W.float w (W.RationalRect 0.1 0.1 0.5 0.5)
    return (All True)
rescueOffscreenHook _ = return (All True)

------------------------------------------------------------------------
-- EWMH fullscreen support
------------------------------------------------------------------------

-- Advertise fullscreen support to EWMH
fullscreenStartupHook :: X ()
fullscreenStartupHook = withDisplay $ \dpy -> do
    r <- asks theRoot
    a <- getAtom "_NET_SUPPORTED"
    c <- getAtom "ATOM"
    f <- getAtom "_NET_WM_STATE_FULLSCREEN"
    io $ do
        sup <- join . maybeToList <$> getWindowProperty32 dpy a r
        unless (fromIntegral f `elem` sup) $
            changeProperty32 dpy r a c propModeAppend [fromIntegral f]
