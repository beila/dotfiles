module XMonadConfig.WindowTags (
    cleanStrayTags,
    lockPropertyActive,
    refreshTagMetrics,
    tagMetricValues,
    titleTagRectangle,
    windowTagEventHook,
    windowTags,
    withSessionPrefix,
) where

import Control.Monad (filterM, forM, forM_, unless, when)
import qualified Data.ByteString as BS
import qualified Data.List as L
import qualified Data.Map as M
import Data.Maybe (fromMaybe)
import Data.Monoid (All (..))
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Text.Read (readMaybe)
import XMonad
import qualified XMonad.StackSet as W
import qualified XMonad.Util.ExtensibleState as XS
import XMonad.Util.Font (Align (AlignLeft), XMonadFont, initXMF)
import XMonad.Util.Run (runProcessWithInput)
import XMonad.Util.XUtils (createNewWindow, deleteWindow, fi, paintAndWrite, showWindow)
import qualified XMonadConfig.Constants as C

data TagMetrics = TagMetrics
    { tmFont :: Int
    , tmDpi :: Int
    , tmHeight :: Dimension
    }
    deriving (Eq, Show, Read, Typeable)

defaultTagMetrics :: TagMetrics
defaultTagMetrics = TagMetrics 11 96 24

newtype TagMetricsState = TagMetricsState TagMetrics
    deriving (Typeable)

instance ExtensionClass TagMetricsState where
    initialValue = TagMetricsState defaultTagMetrics
    extensionType = StateExtension

readTagMetrics :: IO TagMetrics
readTagMetrics = do
    output <- runProcessWithInput "xrdb" ["-query"] ""
    let resourceDatabase =
            [ (key, dropWhile (`elem` " \t") (drop 1 rest))
            | line <- lines output
            , let (key, rest) = break (== ':') line
            , not (null rest)
            ]
        number key fallback = fromMaybe fallback (lookup key resourceDatabase >>= readMaybe) :: Double
        (font, dpi, height) =
            tagMetricValues
                (number "Xft.dpi" 96)
                (number "xmonad.tag.fontSize" 11)
                (number "xmonad.tag.height" 24)
    return
        TagMetrics
            { tmFont = font
            , tmDpi = dpi
            , tmHeight = height
            }

tagMetricValues :: Double -> Double -> Double -> (Int, Int, Dimension)
tagMetricValues requestedDpi baseFont baseHeight =
    ( max 11 (round baseFont)
    , dpi
    , max 24 (round (baseHeight * scale))
    )
  where
    dpi = max 96 (round requestedDpi)
    scale = fromIntegral dpi / 96

refreshTagMetrics :: X ()
refreshTagMetrics = do
    metrics <- io readTagMetrics
    XS.put (TagMetricsState metrics)
    windowTags

windowTagEventHook :: Event -> X All
windowTagEventHook PropertyEvent{ev_window = window, ev_atom = atom} = do
    root <- asks theRoot
    resourceManager <- getAtom "RESOURCE_MANAGER"
    lockState <- getAtom "_XMONAD_SCREEN_LOCKED"
    when (window == root) $
        if atom == resourceManager
            then refreshTagMetrics
            else when (atom == lockState) windowTags
    return (All True)
windowTagEventHook _ = return (All True)

tagFontName :: TagMetrics -> String
tagFontName metrics =
    "xft:JetBrainsMono Nerd Font:size="
        ++ show (tmFont metrics)
        ++ ":dpi="
        ++ show (tmDpi metrics)

tagHeight :: TagMetrics -> Dimension
tagHeight = tmHeight

titleTagRectangle :: Position -> Position -> Dimension -> Dimension -> Rectangle
titleTagRectangle clientX clientY clientWidth height =
    Rectangle
        (clientX + fi clientWidth - fi width)
        clientY
        width
        height
  where
    width = max 1 (clientWidth `div` 2)

data WindowTagEntry = WindowTagEntry
    { tagWindow :: Window
    , tagRectangle :: Rectangle
    , tagTitle :: String
    , tagIsActive :: Bool
    , tagMetrics :: TagMetrics
    }

newtype WindowTags = WindowTags (M.Map Window WindowTagEntry)

instance ExtensionClass WindowTags where
    initialValue = WindowTags M.empty
    extensionType = StateExtension

newtype TagFont = TagFont (Maybe (String, XMonadFont))

instance ExtensionClass TagFont where
    initialValue = TagFont Nothing
    extensionType = StateExtension

tagFont :: TagMetrics -> X XMonadFont
tagFont metrics = do
    TagFont cached <- XS.get
    let name = tagFontName metrics
    case cached of
        Just (oldName, font) | oldName == name -> return font
        _ -> do
            font <- initXMF name
            XS.put (TagFont (Just (name, font)))
            return font

windowPropertyUtf8 :: String -> Window -> X (Maybe String)
windowPropertyUtf8 property window = do
    atom <- getAtom property
    withDisplay $ \display ->
        io $
            fmap (T.unpack . TE.decodeUtf8 . BS.pack . map fromIntegral)
                <$> getWindowProperty8 display atom window

withSessionPrefix :: Maybe String -> String -> String
withSessionPrefix Nothing name = name
withSessionPrefix (Just "") name = name
withSessionPrefix (Just session) name
    | prefix `L.isPrefixOf` name = name
    | null name = prefix
    | otherwise = prefix ++ " " ++ name
  where
    prefix = "[" ++ session ++ "]"

lockPropertyActive :: (Eq a, Num a) => Maybe [a] -> Bool
lockPropertyActive = maybe False (elem 1)

screenLocked :: X Bool
screenLocked = do
    root <- asks theRoot
    atom <- getAtom "_XMONAD_SCREEN_LOCKED"
    withDisplay $ \display ->
        lockPropertyActive <$> io (getWindowProperty32 display atom root)

clearWindowTags :: X ()
clearWindowTags = do
    WindowTags cache <- XS.get
    forM_ (M.elems cache) $ deleteWindow . tagWindow
    XS.put (WindowTags M.empty)

windowTags :: X ()
windowTags = do
    locked <- screenLocked
    if locked then clearWindowTags else renderWindowTags

renderWindowTags :: X ()
renderWindowTags = withWindowSet $ \stackSet -> do
    TagMetricsState metrics <- XS.get
    let visible = concatMap (W.integrate' . W.stack . W.workspace) (W.current stackSet : W.visible stackSet)
        focused = W.peek stackSet
    candidates <- filterM (runQuery (className =? C.ghosttyClass)) visible
    WindowTags cache <- XS.get
    font <- tagFont metrics
    kept <- forM candidates $ \client -> do
        attributes <- withDisplay $ \display -> io $ getWindowAttributes display client
        titleName <- runQuery title client
        session <- windowPropertyUtf8 "_ZMX_SESSION" client
        let name = withSessionPrefix session titleName
            height = tagHeight metrics
            rectangle = titleTagRectangle (fi (wa_x attributes)) (fi (wa_y attributes)) (fi (wa_width attributes)) height
            width = rect_width rectangle
            active = focused == Just client
        overlay <- case M.lookup client cache of
            Just entry
                | tagRectangle entry == rectangle
                    && tagTitle entry == name
                    && tagIsActive entry == active
                    && tagMetrics entry == metrics ->
                    return $ tagWindow entry
                | otherwise -> do
                    let existing = tagWindow entry
                    withDisplay $ \display -> io $ moveResizeWindow display existing (rect_x rectangle) (rect_y rectangle) width height
                    paintTag existing font width height name active
                    return existing
            Nothing -> do
                created <- createNewWindow rectangle Nothing "" True
                -- Name overlays so startup cleanup can find restart leftovers.
                withDisplay $ \display -> io $ setClassHint display created (ClassHint "xmonad-window-tag" "xmonad")
                showWindow created
                paintTag created font width height name active
                return created
        withDisplay $ \display -> io $ raiseWindow display overlay
        return
            ( client
            , WindowTagEntry
                { tagWindow = overlay
                , tagRectangle = rectangle
                , tagTitle = name
                , tagIsActive = active
                , tagMetrics = metrics
                }
            )
    forM_ (M.toList cache) $ \(client, entry) ->
        unless (client `elem` candidates) $ deleteWindow (tagWindow entry)
    XS.put (WindowTags (M.fromList kept))

paintTag :: Window -> XMonadFont -> Dimension -> Dimension -> String -> Bool -> X ()
paintTag overlay font width height name active =
    paintAndWrite
        overlay
        font
        width
        height
        1
        C.backgroundColor
        (if active then C.focusAccentColor else C.inactiveTagBorderColor)
        (if active then C.focusAccentColor else C.inactiveTagTextColor)
        C.backgroundColor
        [AlignLeft]
        [name]

cleanStrayTags :: X ()
cleanStrayTags = withDisplay $ \display -> do
    root <- asks theRoot
    io $ do
        (_, _, children) <- queryTree display root
        forM_ children $ \child -> do
            hint <- getClassHint display child
            when (resName hint `elem` ["xmonad-window-tag", "xmonad-float-tag", "xmonad-decoration"]) $
                destroyWindow display child
    XS.put (WindowTags M.empty)
