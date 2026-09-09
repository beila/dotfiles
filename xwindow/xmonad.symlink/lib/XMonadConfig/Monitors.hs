module XMonadConfig.Monitors (
    MonitorTarget (..),
    classifyMonitor,
    shouldRescueOffscreen,
) where

import qualified Data.ByteString as BS
import qualified Data.List as L
import XMonad (Rectangle (..))

data MonitorTarget
    = DellMonitor
    | SamsungMonitor
    | LaptopMonitor
    deriving (Eq, Show)

classifyMonitor :: String -> Maybe BS.ByteString -> Maybe MonitorTarget
classifyMonitor output vendor
    | "eDP-" `L.isPrefixOf` output = Just LaptopMonitor
    | vendor == Just (BS.pack [0x10, 0xac]) = Just DellMonitor
    | vendor == Just (BS.pack [0x4c, 0x2d]) = Just SamsungMonitor
    | otherwise = Nothing

shouldRescueOffscreen :: [Rectangle] -> Int -> Int -> Int -> Int -> Bool
shouldRescueOffscreen rects x y width height =
    width > 100
        && height > 100
        && case virtualDesktopExtent rects of
            Just (right, bottom) ->
                x >= right || y >= bottom || x < -500 || y < -500
            Nothing -> False

virtualDesktopExtent :: [Rectangle] -> Maybe (Int, Int)
virtualDesktopExtent [] = Nothing
virtualDesktopExtent rects =
    Just
        ( maximum $ map (\r -> fromIntegral (rect_x r) + fromIntegral (rect_width r)) rects
        , maximum $ map (\r -> fromIntegral (rect_y r) + fromIntegral (rect_height r)) rects
        )
