import XMonad
import XMonad.Hooks.SetWMName

main = xmonad defaultConfig
	-- https://bbs.archlinux.org/viewtopic.php?pid=744577#p744577
	{ startupHook = setWMName "LG3D"
	, modMask = mod4Mask
	}
