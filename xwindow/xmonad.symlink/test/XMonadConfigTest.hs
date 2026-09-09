module XMonadConfigTest (main) where

import Control.Exception (SomeException, displayException, try)
import Control.Monad (forM_, unless)
import qualified Data.ByteString as BS
import qualified Data.Map as M
import qualified Main as Config
import System.Exit (exitFailure)
import XMonad
import qualified XMonad.StackSet as W
import qualified XMonadConfig.Constants as C
import qualified XMonadConfig.Monitors as Monitors
import qualified XMonadConfig.Scratchpad as S

data Test = Test String (IO ())

main :: IO ()
main = do
    failures <- runTests tests
    unless (null failures) exitFailure

runTests :: [Test] -> IO [String]
runTests cases = do
    failures <- traverse runTest cases
    let failed = concat failures
    if null failed
        then putStrLn $ "PASS: " ++ show (length cases) ++ " xmonad tests"
        else forM_ failed $ \failure -> putStrLn $ "FAIL: " ++ failure
    pure failed

runTest :: Test -> IO [String]
runTest (Test name action) = do
    result <- try action
    pure $ case result of
        Left exception -> [name ++ ": " ++ displayException (exception :: SomeException)]
        Right () -> []

assertEqual :: (Eq a, Show a) => String -> a -> a -> IO ()
assertEqual name expected actual =
    unless (actual == expected) $
        fail $
            name ++ ": expected " ++ show expected ++ ", got " ++ show actual

tests :: [Test]
tests =
    [ Test "session prefix absent" $
        assertEqual "title" "shell" (Config.withSessionPrefix Nothing "shell")
    , Test "empty session prefix ignored" $
        assertEqual "title" "shell" (Config.withSessionPrefix (Just "") "shell")
    , Test "session prefix prepended" $
        assertEqual "title" "[work] shell" (Config.withSessionPrefix (Just "work") "shell")
    , Test "session prefix idempotent" $
        assertEqual "title" "[work] shell" (Config.withSessionPrefix (Just "work") "[work] shell")
    , Test "session prefix handles empty title" $
        assertEqual "title" "[work]" (Config.withSessionPrefix (Just "work") "")
    , Test "landscape left scratchpad rectangle" $
        assertEqual
            "rectangle"
            (W.RationalRect 0.01 0.03 0.485 0.94)
            (S.scratchpadRect True (Rectangle 0 0 3840 2400))
    , Test "landscape right scratchpad rectangle" $
        assertEqual
            "rectangle"
            (W.RationalRect 0.505 0.03 0.485 0.94)
            (S.scratchpadRect False (Rectangle 0 0 3840 2400))
    , Test "portrait top scratchpad rectangle" $
        assertEqual
            "rectangle"
            (W.RationalRect 0.01 0.03 0.98 0.47)
            (S.scratchpadRect True (Rectangle 0 0 1440 2560))
    , Test "portrait bottom scratchpad rectangle" $
        assertEqual
            "rectangle"
            (W.RationalRect 0.01 0.51 0.98 0.47)
            (S.scratchpadRect False (Rectangle 0 0 1440 2560))
    , Test "hidden workspace view preserves current screen" $ do
        let before = testStackSet
            after = Config.greedyViewNoSwap "3" before
        assertEqual "current workspace" "3" (W.currentTag after)
        assertEqual "visible workspace" ["2"] (map (W.tag . W.workspace) (W.visible after))
    , Test "visible workspace view swaps without changing screen order" $ do
        let before = testStackSet
            after = Config.greedyViewNoSwap "2" before
        assertEqual "current workspace" "2" (W.currentTag after)
        assertEqual "visible workspace" ["1"] (map (W.tag . W.workspace) (W.visible after))
        assertEqual "screen ids" [0, 1] (map W.screen (W.screens after))
    , Test "Super+B strut toggle is unbound" $
        assertEqual
            "Super+B binding"
            False
            (M.member (mod4Mask, xK_b) (keys Config.myConfig keyConfig))
    , Test "workspace identifiers retain key order" $
        assertEqual
            "workspaces"
            ["1:browser", "2:mail", "3:nvim", "4", "5", "6", "7:calendar", "8:meeting", "9:messenger"]
            C.workspaceIds
    , Test "scratchpad identifiers remain distinct" $ do
        assertEqual "names" ["ghostty1", "ghostty2"] (map C.scratchpadName C.allScratchpadSlots)
        assertEqual "instances" ["scratchpad1", "scratchpad2"] (map C.scratchpadInstance C.allScratchpadSlots)
    , Test "missing scratchpad starts" $
        assertEqual "action" S.StartScratchpad (S.decideScratchpadAction Nothing)
    , Test "focused fullscreen scratchpad toggles workspace" $
        assertEqual
            "action"
            S.TogglePreviousWorkspace
            (S.decideScratchpadAction $ Just $ scratchpadContext True True True True)
    , Test "parked fullscreen scratchpad receives focus" $
        assertEqual
            "action"
            S.FocusFullscreenScratchpad
            (S.decideScratchpadAction $ Just $ scratchpadContext False True False True)
    , Test "hidden fullscreen scratchpad is shown and refloated" $
        assertEqual
            "action"
            S.ShowScratchpadAndRefloat
            (S.decideScratchpadAction $ Just $ scratchpadContext False True False False)
    , Test "focused floating scratchpad hides" $
        assertEqual
            "action"
            S.HideScratchpad
            (S.decideScratchpadAction $ Just $ scratchpadContext True False True True)
    , Test "visible floating scratchpad receives focus and refloats" $
        assertEqual
            "action"
            S.FocusScratchpadAndRefloat
            (S.decideScratchpadAction $ Just $ scratchpadContext False False True True)
    , Test "hidden floating scratchpad is shown and refloated" $
        assertEqual
            "action"
            S.ShowScratchpadAndRefloat
            (S.decideScratchpadAction $ Just $ scratchpadContext False False False False)
    , Test "laptop monitor is identified by output name" $
        assertEqual
            "monitor"
            (Just Monitors.LaptopMonitor)
            (Monitors.classifyMonitor "eDP-1" Nothing)
    , Test "laptop output name takes precedence over EDID" $
        assertEqual
            "monitor"
            (Just Monitors.LaptopMonitor)
            (Monitors.classifyMonitor "eDP-1" $ Just $ BS.pack [0x10, 0xac])
    , Test "Dell monitor is identified by EDID vendor" $
        assertEqual
            "monitor"
            (Just Monitors.DellMonitor)
            (Monitors.classifyMonitor "DP-1" $ Just $ BS.pack [0x10, 0xac])
    , Test "Samsung monitor is identified by EDID vendor" $
        assertEqual
            "monitor"
            (Just Monitors.SamsungMonitor)
            (Monitors.classifyMonitor "DP-2" $ Just $ BS.pack [0x4c, 0x2d])
    , Test "unknown external monitor is ignored" $
        assertEqual
            "monitor"
            Nothing
            (Monitors.classifyMonitor "DP-3" $ Just $ BS.pack [0x12, 0x34])
    , Test "large offscreen window is rescued" $
        assertEqual
            "rescue"
            True
            (Monitors.shouldRescueOffscreen testMonitorRects 3841 200 800 600)
    , Test "desktop edge remains on screen" $
        assertEqual
            "rescue"
            False
            (Monitors.shouldRescueOffscreen testMonitorRects 3840 2400 800 600)
    , Test "negative rescue threshold is exclusive" $
        assertEqual
            "rescue"
            False
            (Monitors.shouldRescueOffscreen testMonitorRects (-500) (-500) 800 600)
    , Test "window beyond negative rescue threshold is rescued" $
        assertEqual
            "rescue"
            True
            (Monitors.shouldRescueOffscreen testMonitorRects (-501) 200 800 600)
    , Test "tiny offscreen windows are ignored" $
        assertEqual
            "rescue"
            False
            (Monitors.shouldRescueOffscreen testMonitorRects 9000 9000 100 100)
    , Test "missing screen geometry does not rescue" $
        assertEqual
            "rescue"
            False
            (Monitors.shouldRescueOffscreen [] 9000 9000 800 600)
    ]

testStackSet :: W.StackSet String () Window Int ()
testStackSet = W.new () ["1", "2", "3"] [(), ()]

keyConfig :: XConfig Layout
keyConfig = def{layoutHook = Layout Full}

scratchpadContext :: Bool -> Bool -> Bool -> Bool -> S.ScratchpadContext
scratchpadContext focused fullscreen visible onRealWorkspace =
    S.ScratchpadContext
        { S.isFocused = focused
        , S.isFullscreen = fullscreen
        , S.isVisible = visible
        , S.isOnRealWorkspace = onRealWorkspace
        }

testMonitorRects :: [Rectangle]
testMonitorRects =
    [ Rectangle 0 0 1920 1200
    , Rectangle 1920 0 1920 2400
    ]
