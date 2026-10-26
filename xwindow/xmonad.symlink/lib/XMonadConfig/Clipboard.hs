module XMonadConfig.Clipboard (
    needsControlCopyFallback,
)
where

import Data.Char (toLower)
import Data.List (isInfixOf)

needsControlCopyFallback :: String -> String -> Bool
needsControlCopyFallback appClass windowTitle =
    map toLower appClass == "firefox"
        && "telegram web" `isInfixOf` map toLower windowTitle
