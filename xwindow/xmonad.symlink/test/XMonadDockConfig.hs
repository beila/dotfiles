module XMonadDockConfig (main) where

import qualified Main as Config
import XMonad
import XMonad.Hooks.ManageDocks (ToggleStruts (ToggleStruts), docks)
import XMonad.Util.EZConfig (additionalKeys)
import qualified XMonadConfig.Hooks as Hooks

main :: IO ()
main =
    xmonad $
        docks
            Config.myConfig
                { startupHook = Config.resetStrutsOnStartup
                , logHook = Hooks.raiseFocused
                }
            `additionalKeys` [((mod4Mask .|. shiftMask, xK_b), sendMessage ToggleStruts)]
