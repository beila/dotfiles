module XMonadConfig.Hooks
    ( followToCurrentWorkspace
    , fullscreenStartupHook
    , raiseFocused
    , raiseOsdWindows
    , rescueOffscreenHook
    , stripZoomFullscreenHook
    ) where

import Control.Monad (filterM, forM_, join, unless, when)
import qualified Data.Map as M
import Data.Maybe (fromMaybe, maybeToList)
import Data.Monoid (All (..))
import XMonad
import qualified XMonad.StackSet as W
import qualified XMonad.Util.ExtensibleState as XS
import qualified XMonadConfig.Monitors as Monitors
import qualified XMonadConfig.Stacking as Stacking

followToCurrentWorkspace :: Query Bool -> X ()
followToCurrentWorkspace query = withWindowSet $ \stackSet -> do
    let currentWorkspace = W.tag . W.workspace . W.current $ stackSet
        currentWindows = W.integrate' . W.stack . W.workspace . W.current $ stackSet
    matches <- filterM (runQuery query) (W.allWindows stackSet)
    forM_ matches $ \window ->
        unless (window `elem` currentWindows) $
            windows $
                W.shiftWin currentWorkspace window

rescueOffscreenHook :: Event -> X All
rescueOffscreenHook ConfigureEvent{ev_window = window, ev_x = x, ev_y = y, ev_width = width, ev_height = height} = do
    screens <- withWindowSet $ return . W.screens
    let rectangles = map (screenRect . W.screenDetail) screens
    when
        ( Monitors.shouldRescueOffscreen
            rectangles
            (fromIntegral x)
            (fromIntegral y)
            (fromIntegral width)
            (fromIntegral height)
        )
        $ withWindowSet
        $ \stackSet ->
            when (M.member window $ W.floating stackSet) $
                windows $
                    W.float window (W.RationalRect 0.1 0.1 0.5 0.5)
    return (All True)
rescueOffscreenHook _ = return (All True)

stripZoomFullscreenHook :: Event -> X All
stripZoomFullscreenHook PropertyEvent{ev_window = window, ev_atom = changedAtom} = do
    wmState <- getAtom "_NET_WM_STATE"
    netName <- getAtom "_NET_WM_NAME"
    when (changedAtom == wmState || changedAtom == netName || changedAtom == wM_NAME) $ do
        windowClass <- runQuery className window
        windowTitle <- runQuery title window
        when (windowClass == "zoom" && windowTitle == "Meeting") $ do
            fullscreen <- getAtom "_NET_WM_STATE_FULLSCREEN"
            atom <- getAtom "ATOM"
            withDisplay $ \display -> io $ do
                currentState <- fromMaybe [] <$> getWindowProperty32 display wmState window
                let updatedState = filter (/= fromIntegral fullscreen) currentState
                when (updatedState /= currentState) $
                    changeProperty32 display window wmState atom propModeReplace updatedState
            windows $ W.sink window
    return (All True)
stripZoomFullscreenHook _ = return (All True)

newtype LastFocused = LastFocused Window
    deriving (Typeable)

instance ExtensionClass LastFocused where
    initialValue = LastFocused 0

raiseFocused :: X ()
raiseFocused = withFocused $ \window -> do
    LastFocused previous <- XS.get
    when (window /= previous) $ do
        XS.put (LastFocused window)
        floats <- gets (W.floating . windowset)
        isFirefox <- runQuery (className =? "firefox") window
        when (Stacking.shouldRaiseFocused (M.member window floats) isFirefox) $ do
            withDisplay $ \display -> io $ do
                raiseWindow display window
                mapM_ (raiseWindow display) (M.keys floats)
            isMouseFocused <- asks mouseFocused
            unless isMouseFocused $ clearEvents enterWindowMask

raiseOsdWindows :: X ()
raiseOsdWindows = withDisplay $ \display -> do
    root <- asks theRoot
    io $ do
        (_, _, children) <- queryTree display root
        forM_ children $ \child -> do
            hint <- getClassHint display child
            when (resName hint == "osd") $ raiseWindow display child

fullscreenStartupHook :: X ()
fullscreenStartupHook = withDisplay $ \display -> do
    root <- asks theRoot
    supported <- getAtom "_NET_SUPPORTED"
    atom <- getAtom "ATOM"
    fullscreen <- getAtom "_NET_WM_STATE_FULLSCREEN"
    io $ do
        advertised <- join . maybeToList <$> getWindowProperty32 display supported root
        unless (fromIntegral fullscreen `elem` advertised) $
            changeProperty32 display root supported atom propModeAppend [fromIntegral fullscreen]
