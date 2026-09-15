module XMonadTestClient (main) where

import Control.Concurrent (threadDelay)
import Control.Monad (forever)
import Graphics.X11.Xlib
import Graphics.X11.Xlib.Extras (ClassHint (..), setClassHint)
import System.Environment (getArgs)
import System.Exit (die)

main :: IO ()
main = do
    args <- getArgs
    (overrideRedirect, resourceName, windowClass, windowTitle) <-
        case args of
            [className, title] ->
                return (False, "xmonad-test-client", className, title)
            ["--override", resource, className, title] ->
                return (True, resource, className, title)
            _ ->
                die "usage: xmonad-test-client [--override RESOURCE] CLASS TITLE"
    display <- openDisplay ""
    let screenNumber = defaultScreen display
        screen = defaultScreenOfDisplay display
    root <- rootWindow display screenNumber
    window <-
        if overrideRedirect
            then
                allocaSetWindowAttributes $ \attributes -> do
                    set_override_redirect attributes True
                    createWindow
                        display
                        root
                        50
                        50
                        400
                        300
                        0
                        (defaultDepthOfScreen screen)
                        inputOutput
                        (defaultVisualOfScreen screen)
                        cWOverrideRedirect
                        attributes
            else createSimpleWindow display root 50 50 400 300 0 0 0
    setClassHint display window (ClassHint resourceName windowClass)
    storeName display window windowTitle
    mapWindow display window
    sync display False
    forever $ threadDelay 1000000
