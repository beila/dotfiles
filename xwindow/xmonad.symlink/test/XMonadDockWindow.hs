module XMonadDockWindow (main) where

import Control.Concurrent (threadDelay)
import Control.Monad (forever)
import Graphics.X11.Xlib
import Graphics.X11.Xlib.Extras

main :: IO ()
main = do
    display <- openDisplay ""
    let screen = defaultScreen display
        width = fromIntegral (displayWidth display screen) :: Int
        height = fromIntegral (displayHeight display screen) :: Int
        dockHeight = 48
    root <- rootWindow display screen
    window <-
        createSimpleWindow
            display
            root
            0
            (fromIntegral $ height - dockHeight)
            (fromIntegral width)
            (fromIntegral dockHeight)
            0
            0
            0
    wmType <- internAtom display "_NET_WM_WINDOW_TYPE" False
    dockType <- internAtom display "_NET_WM_WINDOW_TYPE_DOCK" False
    strut <- internAtom display "_NET_WM_STRUT" False
    strutPartial <- internAtom display "_NET_WM_STRUT_PARTIAL" False
    atom <- internAtom display "ATOM" False
    cardinal <- internAtom display "CARDINAL" False
    changeProperty32 display window wmType atom propModeReplace [fromIntegral dockType]
    changeProperty32 display window strut cardinal propModeReplace [0, 0, 0, fromIntegral dockHeight]
    changeProperty32
        display
        window
        strutPartial
        cardinal
        propModeReplace
        [0, 0, 0, fromIntegral dockHeight, 0, 0, 0, 0, 0, 0, 0, fromIntegral width - 1]
    storeName display window "xmonad-dock-test-panel"
    mapWindow display window
    sync display False
    forever $ threadDelay 1000000
