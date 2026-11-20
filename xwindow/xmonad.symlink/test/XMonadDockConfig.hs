module XMonadDockConfig (main) where

import qualified Main as Config
import XMonad
import XMonad.Hooks.ManageDocks (ToggleStruts (ToggleStruts), docks)
import XMonad.Util.EZConfig (additionalKeys)
import qualified XMonadConfig.Hooks as Hooks
import qualified XMonadConfig.WindowTags as WindowTags

main :: IO ()
main =
    xmonad $
        docks
            Config.myConfig
                { startupHook = Config.resetStrutsOnStartup >> Hooks.rootPropertyStartupHook
                , logHook = Hooks.raiseFocused >> WindowTags.windowTags
                }
            `additionalKeys` [ ((mod4Mask .|. shiftMask, xK_b), sendMessage ToggleStruts)
                             , ((mod4Mask .|. shiftMask, xK_o), Hooks.raiseOsdWindows)
                             ]
