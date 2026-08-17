import Control.Monad
import Data.List (stripPrefix)
import qualified Data.List as L (filter, find, isSuffixOf)
import qualified Data.Map as M (Map, empty, fromList, keys, lookup, member, toList)
import Data.Maybe
import Text.Read (readMaybe)
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
import XMonad.Layout.NoBorders (smartBorders)
import XMonad.Util.EZConfig (additionalKeys)
import qualified XMonad.Util.ExtensibleState as XS
import XMonad.Util.Font (Align (..), XMonadFont, initXMF)
import XMonad.Util.NamedScratchpad
import XMonad.Util.Run (runProcessWithInput)
import XMonad.Util.XUtils (createNewWindow, deleteWindow, fi, paintAndWrite, showWindow)

import Graphics.X11.ExtraTypes.XF86
import Graphics.X11.Xlib.Window (raiseWindow)

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
                , fullscreenStartupHook
                , spawn "pgrep xfce4-panel || xfce4-panel"
                , spawn "pgrep -fx albert >/dev/null || albert"
                , cleanStrayTags
                , refreshTagMetrics
                , -- Safety net for fresh checkouts: map keycodes 198/202 →
                  -- F20/F24 for the keyd Super+V/C macro. system-deps.sh
                  -- patches inet durably; this xmodmap covers the gap until
                  -- script/install runs.
                  spawn "xmodmap -e 'keycode 198 = F20' -e 'keycode 202 = F24'"
                ]
        , handleEventHook = handleEventHook gnomeConfig <> rescueOffscreenHook <> stripZoomFullscreenHook <> refreshTagMetricsHook
        , logHook = logHook gnomeConfig >> followToCurrentWorkspace (title =? "zoom_linux_float_video_window") >> raiseFocused >> windowTags >> raiseOsdWindows
        , modMask = mod4Mask
        , -- https://wiki.haskell.org/Xmonad/General_xmonad.hs_config_tips#ManageHook_examples
          workspaces = myWorkspaces
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
        , focusedBorderColor = "#F8BB3D"
        , normalBorderColor = "#1d1d1d"
        }
        `additionalKeys` myKeys

myWorkspaces = ["1:browser", "2:mail", "3:nvim", "4", "5", "6", "7:calendar", "8:meeting", "9:messenger"]

------------------------------------------------------------------------
-- Window tag (top-right corner)
------------------------------------------------------------------------

-- A short title tag pinned over the top-right corner of each visible ghostty.
-- ghostty runs without window decorations and the panel has no tasklist, so the
-- window title -- which zsh/terminal.zsh prefixes with the zmx session name --
-- had nowhere to show. Unlike the prompt it survives a long-running command.
--
-- One overlay path handles both tiled and floating windows. Keeping tags out of
-- the layout avoids stale, serialized Decoration themes after a DPI change.

-- Metrics refresh at startup, after RandR changes, and whenever xrdb replaces
-- RESOURCE_MANAGER. Values can be tuned without touching this file:
--
--   echo 'xmonad.tag.height: 28' | xrdb -merge
--
-- Bases are readable 96dpi-equivalent sizes, multiplied by Xft.dpi/96. The
-- minima prevent stale or undersized resource values from making the title
-- unreadable when a display configuration falls back to Xft.dpi=96.
data TagMetrics = TagMetrics
    { tmFont :: Int
    , tmWidth :: Dimension
    , tmHeight :: Dimension
    }
    deriving (Eq, Show, Read, Typeable)

defaultTagMetrics :: TagMetrics
defaultTagMetrics = TagMetrics 11 320 24

newtype TagMetricsState = TagMetricsState TagMetrics
    deriving (Typeable)

instance ExtensionClass TagMetricsState where
    initialValue = TagMetricsState defaultTagMetrics
    extensionType = StateExtension

readTagMetrics :: IO TagMetrics
readTagMetrics = do
    out <- runProcessWithInput "xrdb" ["-query"] ""
    let db =
            [ (key, dropWhile (`elem` " \t") (drop 1 rest))
            | l <- lines out
            , let (key, rest) = break (== ':') l
            , not (null rest)
            ]
        num k d = fromMaybe d (lookup k db >>= readMaybe) :: Double
        scale = max 1 (num "Xft.dpi" 96 / 96)
    return
        TagMetrics
            { tmFont = max 11 (round (num "xmonad.tag.fontSize" 11 * scale))
            , tmWidth = max 240 (round (num "xmonad.tag.width" 320 * scale))
            , tmHeight = max 24 (round (num "xmonad.tag.height" 24 * scale))
            }

refreshTagMetrics :: X ()
refreshTagMetrics = io readTagMetrics >>= XS.put . TagMetricsState

refreshTagMetricsHook :: Event -> X All
refreshTagMetricsHook PropertyEvent{ev_window = w, ev_atom = a} = do
    root <- asks theRoot
    resourceManager <- getAtom "RESOURCE_MANAGER"
    when (w == root && a == resourceManager) refreshTagMetrics
    return (All True)
refreshTagMetricsHook _ = return (All True)

tagFontName :: TagMetrics -> String
tagFontName m = "xft:JetBrainsMono Nerd Font:size=" ++ show (tmFont m)

tagWidth, tagHeight :: TagMetrics -> Dimension
tagWidth = tmWidth
tagHeight = tmHeight

-- The cache includes focus and metrics because both change the pixels even when
-- the title and client rectangle stay unchanged.
data WindowTags = WindowTags (M.Map Window (Window, Rectangle, String, Bool, TagMetrics))

instance ExtensionClass WindowTags where
    initialValue = WindowTags M.empty
    extensionType = StateExtension

data TagFont = TagFont (Maybe (String, XMonadFont))

instance ExtensionClass TagFont where
    initialValue = TagFont Nothing
    extensionType = StateExtension

tagFont :: TagMetrics -> X XMonadFont
tagFont metrics = do
    TagFont cached <- XS.get
    let name = tagFontName metrics
    case cached of
        Just (oldName, f) | oldName == name -> return f
        _ -> do
            f <- initXMF name
            XS.put (TagFont (Just (name, f)))
            return f

windowTags :: X ()
windowTags = withWindowSet $ \ws -> do
    TagMetricsState metrics <- XS.get
    let visible = concatMap (W.integrate' . W.stack . W.workspace) (W.current ws : W.visible ws)
        focused = W.peek ws
    candidates <- filterM (runQuery (className =? "com.mitchellh.ghostty")) visible
    WindowTags cache <- XS.get
    font <- tagFont metrics
    kept <- forM candidates $ \w -> do
        wa <- withDisplay $ \d -> io $ getWindowAttributes d w
        name <- runQuery title w
        let tagW = min (tagWidth metrics) (fi (wa_width wa))
            tagH = tagHeight metrics
            cx = fi (wa_x wa) + fi (wa_width wa) - fi tagW
            rect = Rectangle cx (fi (wa_y wa)) tagW tagH
            active = focused == Just w
        tw <- case M.lookup w cache of
            Just (tw, oldRect, oldName, oldActive, oldMetrics)
                | oldRect == rect && oldName == name && oldActive == active && oldMetrics == metrics -> return tw
                | otherwise -> do
                    withDisplay $ \d -> io $ moveResizeWindow d tw (rect_x rect) (rect_y rect) tagW tagH
                    paintTag tw font tagW tagH name active
                    return tw
            Nothing -> do
                tw <- createNewWindow rect Nothing "" True
                -- Name it so cleanStrayTags can find leftovers after a restart.
                withDisplay $ \d -> io $ setClassHint d tw (ClassHint "xmonad-window-tag" "xmonad")
                showWindow tw
                paintTag tw font tagW tagH name active
                return tw
        -- Clients are raised on focus, so tags that overlap them must follow.
        withDisplay $ \d -> io $ raiseWindow d tw
        return (w, (tw, rect, name, active, metrics))
    forM_ (M.toList cache) $ \(w, (tw, _, _, _, _)) ->
        unless (w `elem` candidates) $ deleteWindow tw
    XS.put (WindowTags (M.fromList kept))
paintTag :: Window -> XMonadFont -> Dimension -> Dimension -> String -> Bool -> X ()
paintTag tw font tagW tagH name active =
    paintAndWrite
        tw
        font
        tagW
        tagH
        1
        "#1d1d1d"
        (if active then "#F8BB3D" else "#69717F")
        (if active then "#F8BB3D" else "#C7CBD1")
        "#1d1d1d"
        [AlignCenter]
        [name]

------------------------------------------------------------------------
-- Scratchpads
------------------------------------------------------------------------

-- Two independent floating ghostty terminals
-- Each opens the zmx session picker; session selection is independent per window
-- Positioning handled by adaptiveFloat based on screen orientation
myScratchpads =
    [ NS
        "ghostty1"
        "ghostty --x11-instance-name=scratchpad1 --working-directory=$HOME -e $HOME/.dotfiles/bin/zmx-select"
        (appName =? "scratchpad1")
        (adaptiveFloat True)
    , NS
        "ghostty2"
        "ghostty --x11-instance-name=scratchpad2 --working-directory=$HOME -e $HOME/.dotfiles/bin/zmx-select"
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
            -- Detect fullscreen from xmonad's float map, not the EWMH atom: exiting
            -- fullscreen runs doSink (setEwmhFullscreenHooks … doSink), which removes
            -- the window from the float map but leaves _NET_WM_STATE_FULLSCREEN set, so
            -- isFullscreen would stay True on a now-tiled window. doFullFloat floats it
            -- at exactly RationalRect 0 0 1 1; anything else is a normal/half-screen state.
            let fullscreen = M.lookup s (W.floating ws) == Just (W.RationalRect 0 0 1 1)
            let visibleWins = concatMap (W.integrate' . W.stack . W.workspace) (W.current ws : W.visible ws)
            let isVisible = s `elem` visibleWins
            if fullscreen
                then -- stuck in its workspace, never hide
                    if isFocused
                        then toggleWS' ["NSP"] -- jump back to previous workspace
                        else case W.findTag s ws of
                            Just tag | tag /= "NSP" -> windows $ W.focusWindow s -- jump to its workspace + focus
                            _ -> do
                                namedScratchpadAction myScratchpads name -- fallback: bring from NSP
                                refloatScratchpad isLeftOrTop isSP
                else -- classic per-window show/hide
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
        , className =? "Anki" --> (ask >>= doF . W.focusWindow)
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
        , className =? "Gnome-panel" --> doFloat
        , appName =? "gnome-panel" --> doFloat
        , className =? "copyq" --> doFloat
        ]

browserRules = shiftAllTo "1:browser" [className =? "firefox"]

mailRules = shiftAllTo "2:mail" [appName =? "Mail", className =? "thunderbird"]

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
            , className =? "zoom" <&&> title /=? "zoom_linux_float_message_reminder" <&&> title /=? "zoom_linux_float_video_window" <&&> title /=? "Meeting"
            , title =? "Meeting chat"
            ]
        , className =? "zoom" <&&> title =? "Meeting" --> doShift "8:meeting" <> (ask >>= doF . W.sink)
        , title =? "zoom_linux_float_message_reminder" --> doFloat <> copyToAllHook <> insertPosition Below Older
        , title =? "zoom_linux_float_video_window" --> doFloat
        -- The annotation toolbar is a small Zoom popup that should float on top
        -- of the meeting, not tile alongside it. doRectFloat (not plain doFloat)
        -- because Zoom's WM_NORMAL_HINTS reports whatever size xmonad last gave
        -- it — under doFloat the window stays at the full tile size from the
        -- previous run. The toolbar's actual content is a single ~80px circular
        -- icon, so size it just big enough for the icon and ditch the padding.
        -- ~3% × 4.5% ≈ 115 × 108 px on 3840×2400 (and scales down proportionally
        -- on smaller displays), centered horizontally near the top.
        , title =? "annotate_toolbar" --> doRectFloat (W.RationalRect 0.485 0.02 0.03 0.045)
        ]

messengerRules =
    shiftAllTo
        "9:messenger"
        [ className =? "yakyak"
        , title =? "WhatsApp - Vivaldi"
        , title =? "WhatsApp - Mozilla Firefox"
        , title `endsWith` "- Gmail — Mozilla Firefox"
        , className =? "Slack"
        ]

endsWith :: Query String -> String -> Query Bool
endsWith q s = fmap (L.isSuffixOf s) q

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

myKeys =
    [ ((mod4Mask .|. mod1Mask, xK_l), spawn "gnome-screensaver-command --lock")
    -- Super+C / Super+V → universal copy/paste, dispatched at keyd level
    -- (see keyd/common's [meta] layer emitting XF86Copy/XF86Paste). xmonad
    -- doesn't see these — keyd swallows the Super and emits a bare keysym
    -- which the focused app handles natively.
    , ((mod4Mask .|. shiftMask, xK_v), spawn "copyq toggle") -- clipboard history picker
    , ((0, xF86XK_TouchpadToggle), spawn "$HOME/.dotfiles/xwindow/bin/albert-toggle") -- Super tap via keyd (prog1 = f21)
    , ((0, xF86XK_TouchpadOn), scratchpadToggle "ghostty1") -- Alt_L tap via keyd (prog2 = f22)
    , ((0, xF86XK_TouchpadOff), scratchpadToggle "ghostty2") -- Alt_R tap via keyd (prog3 = f23)
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
    , ((mod4Mask, xK_s), spawn "scrot -s - | xclip -selection clipboard -t image/png") -- screenshot selection to clipboard
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
        unless (M.member w floats) $ do
            withDisplay $ \dpy -> io $ do
                raiseWindow dpy w
                mapM_ (raiseWindow dpy) (M.keys floats)
            -- Raising the client buries its TopRightTag decoration, which
            -- overlaps the client's top-right corner (see `shrink` there). Lift
            -- the decoration windows back above it; they're identifiable by
            -- their resource class.
            raiseDecorations
            -- Core purges restack-synthesized EnterNotify before the
            -- logHook runs; our raises here re-synthesize them, and with
            -- focusFollowsMouse they'd yank focus back to the window
            -- under the pointer (e.g. keyboard-cycling from a scratchpad
            -- float to a tiled window bounces right back). Purge again,
            -- same guard as core: skip when the change came from the mouse.
            isMouseFocused <- asks mouseFocused
            unless isMouseFocused $ clearEvents enterWindowMask

-- Destroy tag windows left behind by a previous xmonad process. `xmonad
-- --restart` re-execs, and the float tag cache is non-persistent state, so the
-- windows it created survive with nothing tracking them (visible as stale
-- 20x20/320x20 leftovers piling up across restarts). Anything matching at
-- startupHook time predates this process, since no layout has run yet.
cleanStrayTags :: X ()
cleanStrayTags = withDisplay $ \dpy -> do
    root <- asks theRoot
    io $ do
        (_, _, children) <- queryTree dpy root
        forM_ children $ \c -> do
            hint <- getClassHint dpy c
            when (resName hint `elem` ["xmonad-float-tag", "xmonad-decoration"]) $
                destroyWindow dpy c

-- Raise every xmonad decoration window above the clients. Decoration windows
-- carry the resource NAME "xmonad-decoration" (their resource class is plain
-- "xmonad", shared with every other xmonad window -- checking the class would
-- match nothing useful), so a walk of the root's children finds them without
-- tracking them ourselves.
raiseDecorations :: X ()
raiseDecorations = withDisplay $ \dpy -> do
    root <- asks theRoot
    io $ do
        (_, _, children) <- queryTree dpy root
        forM_ children $ \c -> do
            hint <- getClassHint dpy c
            when (resName hint == "xmonad-decoration") $ raiseWindow dpy c

-- Persistent override-redirect OSDs can be covered when raiseFocused lifts a
-- client. Raise them last, after both clients and floating title tags.
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
