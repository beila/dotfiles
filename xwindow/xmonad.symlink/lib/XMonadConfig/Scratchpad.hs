module XMonadConfig.Scratchpad (
    ScratchpadAction (..),
    ScratchpadContext (..),
    decideScratchpadAction,
    scratchpadRect,
)
where

import XMonad (Rectangle (..))
import qualified XMonad.StackSet as W

data ScratchpadContext = ScratchpadContext
    { isFocused :: Bool
    , isFullscreen :: Bool
    , isVisible :: Bool
    , isOnRealWorkspace :: Bool
    }
    deriving (Eq, Show)

data ScratchpadAction
    = StartScratchpad
    | TogglePreviousWorkspace
    | FocusFullscreenScratchpad
    | ShowScratchpadAndRefloat
    | HideScratchpad
    | FocusScratchpadAndRefloat
    deriving (Eq, Show)

decideScratchpadAction :: Maybe ScratchpadContext -> ScratchpadAction
decideScratchpadAction Nothing = StartScratchpad
decideScratchpadAction (Just context)
    | isFullscreen context && isFocused context = TogglePreviousWorkspace
    | isFullscreen context && isOnRealWorkspace context = FocusFullscreenScratchpad
    | isFullscreen context = ShowScratchpadAndRefloat
    | isFocused context = HideScratchpad
    | isVisible context = FocusScratchpadAndRefloat
    | otherwise = ShowScratchpadAndRefloat

scratchpadRect :: Bool -> Rectangle -> W.RationalRect
scratchpadRect isLeftOrTop (Rectangle _ _ screenWidth screenHeight)
    | screenWidth > screenHeight =
        if isLeftOrTop
            then W.RationalRect 0.01 0.03 0.485 0.94
            else W.RationalRect 0.505 0.03 0.485 0.94
    | otherwise =
        if isLeftOrTop
            then W.RationalRect 0.01 0.03 0.98 0.47
            else W.RationalRect 0.01 0.51 0.98 0.47
