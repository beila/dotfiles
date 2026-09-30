module XMonadConfig.Monitors (
    MonitorTarget (..),
    TwoMonitorTarget (..),
    classifyMonitor,
    selectTwoMonitorOutput,
    sysfsOutputCandidates,
    shouldRescueOffscreen,
) where

import qualified Data.ByteString as BS
import Data.Char (isDigit)
import qualified Data.List as L
import XMonad (Rectangle (..))

data MonitorTarget
    = DellMonitor
    | SamsungMonitor
    | LaptopMonitor
    deriving (Eq, Show)

data TwoMonitorTarget
    = InternalDisplay
    | ExternalDisplay
    deriving (Eq, Show)

classifyMonitor :: String -> Maybe BS.ByteString -> Maybe MonitorTarget
classifyMonitor output vendor
    | isInternalOutput output = Just LaptopMonitor
    | vendor == Just (BS.pack [0x10, 0xac]) = Just DellMonitor
    | vendor == Just (BS.pack [0x4c, 0x2d]) = Just SamsungMonitor
    | otherwise = Nothing

selectTwoMonitorOutput :: TwoMonitorTarget -> [(String, a)] -> Maybe a
selectTwoMonitorOutput target outputs =
    case L.partition (isInternalOutput . fst) outputs of
        ([(_, internal)], [(_, external)]) ->
            Just $ case target of
                InternalDisplay -> internal
                ExternalDisplay -> external
        _ -> Nothing

isInternalOutput :: String -> Bool
isInternalOutput = L.isPrefixOf "eDP-"

sysfsOutputCandidates :: String -> [String]
sysfsOutputCandidates output =
    output : case stripProviderSuffix output of
        Just connector -> [connector]
        Nothing -> []
  where
    stripProviderSuffix name =
        case span isDigit (reverse name) of
            ([], _) -> Nothing
            (_, '-' : baseReversed@(baseLast : _))
                | isDigit baseLast ->
                    Just $ reverse baseReversed
            _ -> Nothing

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
