module XMonadDockConfig (main) where

import qualified Main as Config
import XMonad
import XMonad.Hooks.ManageDocks (docks)

main :: IO ()
main =
    xmonad $
        docks
            Config.myConfig
                { startupHook = return ()
                , logHook = return ()
                }
