module XMonadConfigTest (main) where

import Control.Exception (SomeException, displayException, try)
import Control.Monad (forM_, unless)
import qualified Data.Map as M
import qualified Main as Config
import System.Exit (exitFailure)
import XMonad
import qualified XMonad.StackSet as W

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
            (Config.scratchpadRect True (Rectangle 0 0 3840 2400))
    , Test "landscape right scratchpad rectangle" $
        assertEqual
            "rectangle"
            (W.RationalRect 0.505 0.03 0.485 0.94)
            (Config.scratchpadRect False (Rectangle 0 0 3840 2400))
    , Test "portrait top scratchpad rectangle" $
        assertEqual
            "rectangle"
            (W.RationalRect 0.01 0.03 0.98 0.47)
            (Config.scratchpadRect True (Rectangle 0 0 1440 2560))
    , Test "portrait bottom scratchpad rectangle" $
        assertEqual
            "rectangle"
            (W.RationalRect 0.01 0.51 0.98 0.47)
            (Config.scratchpadRect False (Rectangle 0 0 1440 2560))
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
    ]

testStackSet :: W.StackSet String () Window Int ()
testStackSet = W.new () ["1", "2", "3"] [(), ()]

keyConfig :: XConfig Layout
keyConfig = def{layoutHook = Layout Full}
