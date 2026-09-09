module Main where

import Control.Exception (IOException, try)
import Control.Monad
import qualified Data.ByteString as BS
import Data.Either (fromRight)
import Data.List (stripPrefix)
import qualified Data.List as L (find, isPrefixOf, isSuffixOf)
import qualified Data.Map as M (Map, empty, fromList, keys, lookup, member, toList)
import Data.Maybe
import Data.Monoid (All (..))
import System.Directory (getHomeDirectory, listDirectory, setCurrentDirectory)
import qualified XMonad.StackSet as W

import XMonad
import XMonad.Actions.CycleWS
import XMonad.Config.Gnome
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.ManageDocks
import XMonad.Hooks.ManageHelpers
import XMonad.Hooks.Rescreen
import XMonad.Hooks.SetWMName
import XMonad.Layout.NoBorders (smartBorders)
import XMonad.Util.EZConfig (additionalKeys, removeKeys)
import qualified XMonad.Util.ExtensibleState as XS
import XMonad.Util.NamedScratchpad

import Graphics.X11.ExtraTypes.XF86
import Graphics.X11.Xlib.Window (raiseWindow)
import qualified Graphics.X11.Xrandr as RR
import qualified XMonadConfig.Constants as C
import qualified XMonadConfig.Monitors as Monitors
import qualified XMonadConfig.Scratchpad as S
import qualified XMonadConfig.Stacking as Stacking
import qualified XMonadConfig.WindowTags as WindowTags
import qualified XMonadConfig.WindowRules as WindowRules
import qualified XMonadConfig.Workspaces as Workspaces

------------------------------------------------------------------------
-- Main
------------------------------------------------------------------------

main = xmonad $ docks $ ewmhFullscreen $ setEwmhFullscreenHooks fsHook doSink $ rescreenHook monitorHotplugCfg myConfig
  where
    -- Keep Zoom "Meeting" tiled even when it requests fullscreen; default behaviour otherwise
    fsHook = composeOne
        [ className =? "zoom" <&&> title =? "Meeting" -?> idHook
        , pure True -?> doFullFloat
        ]

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
                , -- Clear persisted per-workspace ToggleStruts state.
                  broadcastMessage (SetStruts [minBound .. maxBound] []) >> refresh
                , fullscreenStartupHook
                , spawn "pgrep xfce4-panel || xfce4-panel"
                , spawn "pgrep -fx albert >/dev/null || albert"
                , WindowTags.cleanStrayTags
                , WindowTags.refreshTagMetrics
                , -- Safety net for fresh checkouts: map keycodes 198/202 →
                  -- F20/F24 for the keyd Super+V/C macro. system-deps.sh
                  -- patches inet durably; this xmodmap covers the gap until
                  -- script/install runs.
                  spawn "xmodmap -e 'keycode 198 = F20' -e 'keycode 202 = F24'"
                ]
        , handleEventHook = handleEventHook gnomeConfig <> rescueOffscreenHook <> stripZoomFullscreenHook <> WindowTags.refreshTagMetricsHook
        , logHook = logHook gnomeConfig >> followToCurrentWorkspace (title =? "zoom_linux_float_video_window") >> raiseFocused >> WindowTags.windowTags >> raiseOsdWindows
        , modMask = mod4Mask
        , -- https://wiki.haskell.org/Xmonad/General_xmonad.hs_config_tips#ManageHook_examples
          workspaces = C.workspaceIds
        , -- https://wiki.haskell.org/Xmonad/Config_archive/John_Goerzen's_Configuration#Final_Touches
          -- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#Make_space_for_a_panel_dock_or_tray
          manageHook = myManageHook
        , layoutHook = smartBorders $ avoidStruts $ layoutHook gnomeConfig
        , -- Focus indicator: thin LEGO-orange edge (same accent as
          -- hangul-osd); picom adds a soft warm glow around the focused
          -- window (see home-manager picom.nix). Unfocused border painted
          -- near-invisible instead of 0px so client geometry stays constant
          -- across focus changes (no terminal re-wrap on every switch)
          borderWidth = 1
        , focusedBorderColor = C.focusAccentColor
        , normalBorderColor = C.backgroundColor
        }
        `removeKeys` [(mod4Mask, xK_b)]
        `additionalKeys` myKeys

------------------------------------------------------------------------
-- Scratchpads
------------------------------------------------------------------------

-- Two independent floating ghostty terminals
-- Each opens the zmx session picker; session selection is independent per window
-- Positioning handled by adaptiveFloat based on screen orientation
myScratchpads =
    map scratchpadDefinition C.allScratchpadSlots

scratchpadDefinition :: C.ScratchpadSlot -> NamedScratchpad
scratchpadDefinition slot =
    NS
        (C.scratchpadName slot)
        ("ghostty --x11-instance-name=" ++ C.scratchpadInstance slot ++ " --working-directory=$HOME -e $HOME/.dotfiles/bin/zmx-select")
        (scratchpadQuery slot)
        (adaptiveFloat (C.isLeadingScratchpad slot))

scratchpadQuery :: C.ScratchpadSlot -> Query Bool
scratchpadQuery slot = appName =? C.scratchpadInstance slot

-- Float scratchpad as half the screen, adapting to orientation
adaptiveFloat :: Bool -> ManageHook
adaptiveFloat isLeftOrTop = do
    sc <- liftX $ withWindowSet $ return . screenRect . W.screenDetail . W.current
    doRectFloat (S.scratchpadRect isLeftOrTop sc)

-- Scratchpad toggle (each scratchpad independent — left-alt → ghostty1, right-alt →
-- ghostty2). Behavior depends on whether the scratchpad is fullscreen (ghostty
-- ctrl-enter, holds _NET_WM_STATE_FULLSCREEN):
--
-- Fullscreen — stuck in its own workspace, never hidden (workspace-level navigation):
--   1. Focused → toggleWS' jumps back to the previously viewed workspace (skipping NSP);
--      pressing again returns, toggling between the two workspaces.
--   2. Parked on a real workspace → jump there and focus it, preserving fullscreen.
--
-- Not fullscreen (normal half-screen float) — classic per-window show/hide:
--   3. Focused → hide (move to NSP).
--   4. Visible on another screen → just focus it.
--   5. Hidden → move to current workspace, float, and focus (adapting to orientation).
scratchpadToggle slot = withWindowSet $ \ws -> do
    let name = C.scratchpadName slot
    let isSP = runQuery (scratchpadQuery slot)
    let isLeftOrTop = C.isLeadingScratchpad slot
    let allWins = W.allWindows ws
    spWins <- filterM isSP allWins
    focusedMatches <- case W.peek ws of
        Just w -> isSP w
        Nothing -> return False
    let target = listToMaybe spWins
        visibleWins = concatMap (W.integrate' . W.stack . W.workspace) (W.current ws : W.visible ws)
        context = do
            scratchpad <- target
            return
                S.ScratchpadContext
                    { S.isFocused = focusedMatches
                    , S.isFullscreen = M.lookup scratchpad (W.floating ws) == Just (W.RationalRect 0 0 1 1)
                    , S.isVisible = scratchpad `elem` visibleWins
                    , S.isOnRealWorkspace = maybe False (/= C.hiddenScratchpadWorkspace) (W.findTag scratchpad ws)
                    }
        action = S.decideScratchpadAction context
    case (action, target) of
        (S.StartScratchpad, _) ->
            namedScratchpadAction myScratchpads name
        (S.TogglePreviousWorkspace, _) ->
            toggleWS' [C.hiddenScratchpadWorkspace]
        (S.FocusFullscreenScratchpad, Just scratchpad) ->
            windows $ W.focusWindow scratchpad
        (S.ShowScratchpadAndRefloat, _) -> do
            namedScratchpadAction myScratchpads name
            refloatScratchpad isLeftOrTop isSP
        (S.HideScratchpad, _) ->
            namedScratchpadAction myScratchpads name
        (S.FocusScratchpadAndRefloat, Just scratchpad) -> do
            windows $ W.focusWindow scratchpad
            refloatScratchpad isLeftOrTop isSP
        (_, Nothing) ->
            return ()

-- Find the scratchpad window and refloat it
refloatScratchpad :: Bool -> (Window -> X Bool) -> X ()
refloatScratchpad isLeftOrTop isSP = withWindowSet $ \ws -> do
    let allWins = concatMap (W.integrate' . W.stack . W.workspace) (W.current ws : W.visible ws)
    spWins <- filterM isSP allWins
    case spWins of
        (s : _) -> do
            sc <- withWindowSet $ return . screenRect . W.screenDetail . W.current
            windows $ W.float s (S.scratchpadRect isLeftOrTop sc)
        [] -> return ()

------------------------------------------------------------------------
-- Window rules
------------------------------------------------------------------------

myManageHook =
    composeAll
        [ WindowRules.applicationManageHook
        , manageHook gnomeConfig
        , manageDocks
        , namedScratchpadManageHook myScratchpads
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
monitorHotplugCfg = def{afterRescreenHook = hideNSPWorkspace >> WindowTags.refreshTagMetrics}
hideNSPWorkspace = withWindowSet $ \ws -> do
    let visibleTags = map (W.tag . W.workspace) (W.current ws : W.visible ws)
    when (C.hiddenScratchpadWorkspace `elem` visibleTags) $
        case filter ((/= C.hiddenScratchpadWorkspace) . W.tag) (W.hidden ws) of
            (w : _) -> windows $ W.greedyView (W.tag w)
            [] -> return ()

monitorWorkspace :: ScreenId -> Monitors.MonitorTarget -> X (Maybe WorkspaceId)
monitorWorkspace fallbackScreen target = do
    monitorRects <- withDisplay $ \dpy -> do
        root <- asks theRoot
        io $ findMonitorRects dpy root
    if any ((/= Monitors.LaptopMonitor) . fst) monitorRects
        then case lookup target monitorRects of
            Just rect ->
                withWindowSet $ \ws ->
                    return $
                        fmap (W.tag . W.workspace) $
                            L.find ((== rect) . screenRect . W.screenDetail) $
                                W.screens ws
            Nothing -> return Nothing
        else screenWorkspace fallbackScreen

focusMonitor :: ScreenId -> Monitors.MonitorTarget -> X ()
focusMonitor fallbackScreen target =
    monitorWorkspace fallbackScreen target >>= flip whenJust (windows . W.view)

shiftToMonitor :: ScreenId -> Monitors.MonitorTarget -> X ()
shiftToMonitor fallbackScreen target =
    monitorWorkspace fallbackScreen target >>= flip whenJust (windows . W.shift)

findMonitorRects :: Display -> Window -> IO [(Monitors.MonitorTarget, Rectangle)]
findMonitorRects dpy root = do
    resources <- RR.xrrGetScreenResourcesCurrent dpy root
    case resources of
        Nothing -> return []
        Just rs -> do
            matches <- forM (RR.xrr_sr_outputs rs) $ \output -> do
                outputInfo <- RR.xrrGetOutputInfo dpy rs output
                case outputInfo of
                    Just oi | RR.xrr_oi_crtc oi /= 0 -> do
                        monitorTarget <- identifyMonitor (RR.xrr_oi_name oi)
                        crtcInfo <- RR.xrrGetCrtcInfo dpy rs (RR.xrr_oi_crtc oi)
                        return $ (,) <$> monitorTarget <*> (crtcRect <$> crtcInfo)
                    _ -> return Nothing
            return $ catMaybes matches
  where
    crtcRect ci =
        Rectangle
            (fromIntegral $ RR.xrr_ci_x ci)
            (fromIntegral $ RR.xrr_ci_y ci)
            (fromIntegral $ RR.xrr_ci_width ci)
            (fromIntegral $ RR.xrr_ci_height ci)

identifyMonitor :: String -> IO (Maybe Monitors.MonitorTarget)
identifyMonitor output =
    case Monitors.classifyMonitor output Nothing of
        Just target -> return $ Just target
        Nothing -> Monitors.classifyMonitor output <$> readEdidVendor output

readEdidVendor :: String -> IO (Maybe BS.ByteString)
readEdidVendor output = do
    result <-
        try
            ( do
                connectors <- listDirectory "/sys/class/drm"
                case L.find (L.isSuffixOf $ "-" ++ output) connectors of
                    Nothing -> return Nothing
                    Just connector -> do
                        edid <- BS.readFile $ "/sys/class/drm/" ++ connector ++ "/edid"
                        return $
                            if BS.length edid >= 10
                                then Just $ BS.take 2 $ BS.drop 8 edid
                                else Nothing
            ) ::
            IO (Either IOException (Maybe BS.ByteString))
    return $ fromRight Nothing result

------------------------------------------------------------------------
-- Key bindings
------------------------------------------------------------------------

myKeys =
    [ ((mod4Mask .|. mod1Mask, xK_l), spawn "gnome-screensaver-command --lock")
    -- Super+C / Super+V → universal copy/paste, dispatched at keyd level
    -- (see keyd/common's [meta] layer emitting XF86Copy/XF86Paste). xmonad
    -- doesn't see these — keyd swallows the Super and emits a bare keysym
    -- which the focused app handles natively.
    , ((mod4Mask .|. shiftMask, xK_v), spawn "copyq toggle") -- clipboard history picker
    , ((0, xF86XK_TouchpadToggle), spawn "$HOME/.dotfiles/xwindow/bin/albert-toggle") -- Super tap via keyd (prog1 = f21)
    , ((0, xF86XK_TouchpadOn), scratchpadToggle C.PrimaryScratchpad) -- Alt_L tap via keyd (prog2 = f22)
    , ((0, xF86XK_TouchpadOff), scratchpadToggle C.SecondaryScratchpad) -- Alt_R tap via keyd (prog3 = f23)
    , ((0, xF86XK_AudioRaiseVolume), spawn "$HOME/.dotfiles/xwindow/bin/volume-osd up")
    , ((0, xF86XK_AudioLowerVolume), spawn "$HOME/.dotfiles/xwindow/bin/volume-osd down")
    , ((0, xF86XK_AudioMute), spawn "$HOME/.dotfiles/xwindow/bin/volume-osd toggle")
    , ((0, xF86XK_MonBrightnessUp), spawn "$HOME/.dotfiles/xwindow/bin/brightness-osd up")
    , ((0, xF86XK_MonBrightnessDown), spawn "$HOME/.dotfiles/xwindow/bin/brightness-osd down")
    , ((mod4Mask, xF86XK_AudioRaiseVolume), spawn "$HOME/.dotfiles/xwindow/bin/cycle-audio-output")
    , ((mod4Mask, xF86XK_AudioLowerVolume), spawn "$HOME/.dotfiles/xwindow/bin/cycle-audio-input")
    , ((mod4Mask, xK_w), focusMonitor 0 Monitors.DellMonitor)
    , ((mod4Mask, xK_e), focusMonitor 1 Monitors.SamsungMonitor)
    , ((mod4Mask, xK_r), focusMonitor 2 Monitors.LaptopMonitor)
    , ((mod4Mask .|. shiftMask, xK_w), shiftToMonitor 0 Monitors.DellMonitor)
    , ((mod4Mask .|. shiftMask, xK_e), shiftToMonitor 1 Monitors.SamsungMonitor)
    , ((mod4Mask .|. shiftMask, xK_r), shiftToMonitor 2 Monitors.LaptopMonitor)
    , -- https://hackage.haskell.org/package/xmonad-contrib-0.15/docs/XMonad-Actions-CycleWS.html#v:nextScreen
      ((mod4Mask, xK_quoteleft), nextScreen)
    , ((mod4Mask, xK_equal), nextScreen)
    , ((mod4Mask, xK_0), moveTo Next (emptyWS :&: Not (WSIs $ return (\w -> W.tag w == C.hiddenScratchpadWorkspace)))) -- find a free workspace (skip NSP)
    , ((mod4Mask, xK_s), spawn "scrot -s - | xclip -selection clipboard -t image/png") -- screenshot selection to clipboard
    ]
        ++
        -- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#Replacing_greedyView_with_view
        [ ((m .|. mod4Mask, k), windows $ f i)
        | (i, k) <- zip C.workspaceIds [xK_1 .. xK_9]
        , (f, m) <- [(W.view, 0), (W.shift, shiftMask), (W.greedyView, controlMask), (Workspaces.greedyViewNoSwap, mod2Mask)]
        ]

------------------------------------------------------------------------
-- Rescue offscreen windows (e.g. Zoom moving itself to x=12984)
------------------------------------------------------------------------

rescueOffscreenHook :: Event -> X All
rescueOffscreenHook ConfigureEvent{ev_window = w, ev_x = ex, ev_y = ey, ev_width = ew, ev_height = eh} = do
    screens <- withWindowSet $ return . W.screens
    let rects = map (screenRect . W.screenDetail) screens
    when
        ( Monitors.shouldRescueOffscreen
            rects
            (fromIntegral ex)
            (fromIntegral ey)
            (fromIntegral ew)
            (fromIntegral eh)
        )
        $ withWindowSet
        $ \ws ->
            when (M.member w (W.floating ws)) $
                windows $
                    W.float w (W.RationalRect 0.1 0.1 0.5 0.5)
    return (All True)
rescueOffscreenHook _ = return (All True)

-- Strip _NET_WM_STATE_FULLSCREEN from Zoom "Meeting" windows and sink them.
-- Zoom creates the window titled "Zoom Workplace" and only renames it to
-- "Meeting" after the ManageHook has run, so we can't match it via ManageHook.
-- Instead watch PropertyNotify for _NET_WM_STATE and WM_NAME/_NET_WM_NAME
-- changes; whenever a zoom window becomes titled "Meeting", drop the
-- fullscreen state (Zoom sets it pre-map and via ClientMessage) and re-sink.
stripZoomFullscreenHook :: Event -> X All
stripZoomFullscreenHook PropertyEvent{ev_window = w, ev_atom = a} = do
    wmState <- getAtom "_NET_WM_STATE"
    netName <- getAtom "_NET_WM_NAME"
    when (a == wmState || a == netName || a == wM_NAME) $ do
        cls <- runQuery className w
        tit <- runQuery title w
        when (cls == "zoom" && tit == "Meeting") $ do
            fs <- getAtom "_NET_WM_STATE_FULLSCREEN"
            atom <- getAtom "ATOM"
            withDisplay $ \dpy -> io $ do
                cur <- fromMaybe [] <$> getWindowProperty32 dpy wmState w
                let newState = filter (/= fromIntegral fs) cur
                when (newState /= cur) $
                    changeProperty32 dpy w wmState atom propModeReplace newState
            windows $ W.sink w
    return (All True)
stripZoomFullscreenHook _ = return (All True)

------------------------------------------------------------------------
-- EWMH fullscreen support
------------------------------------------------------------------------

-- Advertise fullscreen support to EWMH
fullscreenStartupHook :: X ()
-- Raise the focused tiled window above other tiled windows so picom's
-- shadow (which renders at the window's Z-level) paints above neighbors.
-- Only fires on actual focus changes (tracked via ExtensibleState) to
-- avoid re-raising on every logHook invocation — that would cover
-- override-redirect popups (dropdowns, menus) which aren't in xmonad's
-- float map.
newtype LastFocused = LastFocused Window
    deriving (Typeable)
instance ExtensionClass LastFocused where
    initialValue = LastFocused 0

raiseFocused :: X ()
raiseFocused = withFocused $ \w -> do
    LastFocused prev <- XS.get
    when (w /= prev) $ do
        XS.put (LastFocused w)
        floats <- gets (W.floating . windowset)
        isFirefox <- runQuery (className =? "firefox") w
        when (Stacking.shouldRaiseFocused (M.member w floats) isFirefox) $ do
            withDisplay $ \dpy -> io $ do
                raiseWindow dpy w
                mapM_ (raiseWindow dpy) (M.keys floats)
            -- Core purges restack-synthesized EnterNotify before the
            -- logHook runs; our raises here re-synthesize them, and with
            -- focusFollowsMouse they'd yank focus back to the window
            -- under the pointer (e.g. keyboard-cycling from a scratchpad
            -- float to a tiled window bounces right back). Purge again,
            -- same guard as core: skip when the change came from the mouse.
            isMouseFocused <- asks mouseFocused
            unless isMouseFocused $ clearEvents enterWindowMask

-- Persistent override-redirect OSDs can be covered when raiseFocused lifts a
-- client. Raise them last, after both clients and title tags.
raiseOsdWindows :: X ()
raiseOsdWindows = withDisplay $ \dpy -> do
    root <- asks theRoot
    io $ do
        (_, _, children) <- queryTree dpy root
        forM_ children $ \c -> do
            hint <- getClassHint dpy c
            when (resName hint == "osd") $ raiseWindow dpy c

fullscreenStartupHook = withDisplay $ \dpy -> do
    r <- asks theRoot
    a <- getAtom "_NET_SUPPORTED"
    c <- getAtom "ATOM"
    f <- getAtom "_NET_WM_STATE_FULLSCREEN"
    io $ do
        sup <- join . maybeToList <$> getWindowProperty32 dpy a r
        unless (fromIntegral f `elem` sup) $
            changeProperty32 dpy r a c propModeAppend [fromIntegral f]
