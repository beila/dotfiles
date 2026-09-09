module XMonadConfig.Constants
    ( ScratchpadSlot (..)
    , allScratchpadSlots
    , backgroundColor
    , browserWorkspace
    , calendarWorkspace
    , editorWorkspace
    , focusAccentColor
    , ghosttyClass
    , hiddenScratchpadWorkspace
    , inactiveTagBorderColor
    , inactiveTagTextColor
    , isLeadingScratchpad
    , mailWorkspace
    , meetingWorkspace
    , messengerWorkspace
    , scratchpadInstance
    , scratchpadName
    , workspaceIds
    )
where

import XMonad (WorkspaceId)

browserWorkspace, mailWorkspace, editorWorkspace, calendarWorkspace, meetingWorkspace, messengerWorkspace :: WorkspaceId
browserWorkspace = "1:browser"
mailWorkspace = "2:mail"
editorWorkspace = "3:nvim"
calendarWorkspace = "7:calendar"
meetingWorkspace = "8:meeting"
messengerWorkspace = "9:messenger"

workspaceIds :: [WorkspaceId]
workspaceIds =
    [ browserWorkspace
    , mailWorkspace
    , editorWorkspace
    , "4"
    , "5"
    , "6"
    , calendarWorkspace
    , meetingWorkspace
    , messengerWorkspace
    ]

hiddenScratchpadWorkspace :: WorkspaceId
hiddenScratchpadWorkspace = "NSP"

data ScratchpadSlot = PrimaryScratchpad | SecondaryScratchpad
    deriving (Bounded, Enum, Eq, Show)

allScratchpadSlots :: [ScratchpadSlot]
allScratchpadSlots = [minBound .. maxBound]

scratchpadName :: ScratchpadSlot -> String
scratchpadName PrimaryScratchpad = "ghostty1"
scratchpadName SecondaryScratchpad = "ghostty2"

scratchpadInstance :: ScratchpadSlot -> String
scratchpadInstance PrimaryScratchpad = "scratchpad1"
scratchpadInstance SecondaryScratchpad = "scratchpad2"

isLeadingScratchpad :: ScratchpadSlot -> Bool
isLeadingScratchpad PrimaryScratchpad = True
isLeadingScratchpad SecondaryScratchpad = False

ghosttyClass :: String
ghosttyClass = "com.mitchellh.ghostty"

focusAccentColor, backgroundColor, inactiveTagBorderColor, inactiveTagTextColor :: String
focusAccentColor = "#F8BB3D"
backgroundColor = "#1d1d1d"
inactiveTagBorderColor = "#69717F"
inactiveTagTextColor = "#C7CBD1"
