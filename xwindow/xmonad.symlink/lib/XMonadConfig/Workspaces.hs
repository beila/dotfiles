module XMonadConfig.Workspaces (
    greedyViewNoSwap,
) where

import qualified Data.List as L
import qualified XMonad.StackSet as W

-- Like greedyView, but keep screen ordering stable when the target is visible.
greedyViewNoSwap :: (Eq s, Eq i) => i -> W.StackSet i l a s sd -> W.StackSet i l a s sd
greedyViewNoSwap workspace stackSet
    | any hasTargetTag (W.hidden stackSet) = W.view workspace stackSet
    | Just targetScreen <- L.find (hasTargetTag . W.workspace) (W.visible stackSet) =
        stackSet
            { W.current = (W.current stackSet){W.workspace = W.workspace targetScreen}
            , W.visible =
                targetScreen{W.workspace = W.workspace (W.current stackSet)}
                    : L.filter (not . hasTargetTag . W.workspace) (W.visible stackSet)
            }
    | otherwise = stackSet
  where
    hasTargetTag = (workspace ==) . W.tag
