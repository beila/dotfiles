module XMonadConfig.Stacking
    ( shouldRaiseFocused
    ) where

shouldRaiseFocused :: Bool -> Bool -> Bool
shouldRaiseFocused isFloating isFirefox = not (isFloating || isFirefox)
