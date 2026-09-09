module XMonadConfig.WindowRules
    ( applicationManageHook
    ) where

import qualified Data.List as L
import XMonad
import XMonad.Actions.CopyWindow (copyWindow)
import XMonad.Hooks.InsertPosition (Focus (Older), Position (Below), insertPosition)
import XMonad.Hooks.ManageHelpers (doLower, doRectFloat, isInProperty, (/=?))
import qualified XMonad.StackSet as W
import qualified XMonadConfig.Constants as C

applicationManageHook :: ManageHook
applicationManageHook =
    composeAll
        [ floatRules
        , className =? "Anki" --> (ask >>= doF . W.focusWindow)
        , browserRules
        , mailRules
        , editorRules
        , calendarRules
        , meetingRules
        , messengerRules
        ]

floatRules :: ManageHook
floatRules =
    composeAll
        [ appName =? "Alert" --> doFloat
        , isInProperty "_NET_WM_WINDOW_TYPE" "_NET_WM_WINDOW_TYPE_DESKTOP" --> doLower
        , className =? "Tilda" --> doFloat
        , className =? "ignition" --> doFloat
        , className =? "Gnome-panel" --> doFloat
        , appName =? "gnome-panel" --> doFloat
        , className =? "copyq" --> doFloat
        ]

browserRules :: ManageHook
browserRules = shiftAllTo C.browserWorkspace [className =? "firefox"]

mailRules :: ManageHook
mailRules = shiftAllTo C.mailWorkspace [appName =? "Mail", className =? "thunderbird"]

editorRules :: ManageHook
editorRules =
    shiftAllTo
        C.editorWorkspace
        [ className =? "jetbrains-clion"
        , className =? "jetbrains-idea"
        , className =? "neovide"
        , className =? "Gvim"
        ]

calendarRules :: ManageHook
calendarRules =
    shiftAllTo
        C.calendarWorkspace
        [ title =? "Ghim, Hojin - Outlook Web App - Vivaldi"
        , title =? "Ghim, Hojin - Outlook Web App - Mozilla Firefox"
        , title =? "Google Calendar - Vivaldi"
        , title =? "Google Calendar - Mozilla Firefox"
        , title =? "Calendar - hojin@amazon.co.uk — Mozilla Firefox"
        , title =? "Email - hojin@amazon.co.uk — Mozilla Firefox"
        ]

meetingRules :: ManageHook
meetingRules =
    composeAll
        [ shiftAllTo
            C.meetingWorkspace
            [ className =? "AmazonChime"
            , title =? "Amazon Chime — Mozilla Firefox"
            , className =? "zoom" <&&> title /=? "zoom_linux_float_message_reminder" <&&> title /=? "zoom_linux_float_video_window" <&&> title /=? "Meeting"
            , title =? "Meeting chat"
            ]
        , className =? "zoom" <&&> title =? "Meeting" --> doShift C.meetingWorkspace <> (ask >>= doF . W.sink)
        , title =? "zoom_linux_float_message_reminder" --> doFloat <> copyToAllHook <> insertPosition Below Older
        , title =? "zoom_linux_float_video_window" --> doFloat
        -- The annotation toolbar reports the full tile in WM_NORMAL_HINTS
        -- after xmonad has resized it, so force its small intended geometry.
        , title =? "annotate_toolbar" --> doRectFloat (W.RationalRect 0.485 0.02 0.03 0.045)
        ]

messengerRules :: ManageHook
messengerRules =
    shiftAllTo
        C.messengerWorkspace
        [ className =? "yakyak"
        , title =? "WhatsApp - Vivaldi"
        , title =? "WhatsApp - Mozilla Firefox"
        , title `endsWith` "- Gmail — Mozilla Firefox"
        , className =? "Slack"
        ]

copyToAllHook :: ManageHook
copyToAllHook = ask >>= \window -> doF (\stackSet -> foldr (copyWindow window . W.tag) stackSet (W.workspaces stackSet))

shiftAllTo :: WorkspaceId -> [Query Bool] -> ManageHook
shiftAllTo workspace = composeAll . map (--> doShift workspace)

endsWith :: Query String -> String -> Query Bool
endsWith query suffix = fmap (L.isSuffixOf suffix) query
