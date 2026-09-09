module XMonadTestClient (main) where

import Control.Concurrent (threadDelay)
import Control.Monad (forever)
import Graphics.X11.Xlib
import Graphics.X11.Xlib.Extras (ClassHint (..), setClassHint)
import System.Environment (getArgs)

main :: IO ()
main = do
    [windowClass, windowTitle] <- getArgs
    display <- openDisplay ""
    let screen = defaultScreen display
    root <- rootWindow display screen
    window <- createSimpleWindow display root 50 50 400 300 0 0 0
    setClassHint display window (ClassHint "xmonad-test-client" windowClass)
    storeName display window windowTitle
    mapWindow display window
    sync display False
    forever $ threadDelay 1000000
