[widget]
s0_match = name=Screenlet.py

[switcher]
as_next_key = Disabled
as_prev_key = Disabled
as_next_all_key = Disabled
as_prev_all_key = Disabled
as_next_no_popup_key = <Control>Tab
as_prev_no_popup_key = <Control>grave
s0_speed = 20.180201
s0_timestep = 0.100000
s0_auto_rotate = true

[addhelper]
as_ononinit = true
as_brightness = 95
as_saturation = 100

[neg]
as_screen_toggle_key = Disabled

[wall]
as_left_key = <Super>Left
as_right_key = <Super>Right
as_up_key = <Super>Up
as_down_key = <Super>Down
as_left_window_key = <Shift><Super>Left
as_right_window_key = <Shift><Super>Right
as_up_window_key = <Shift><Super>Up
as_down_window_key = <Shift><Super>Down

[scaleaddon]
as_close_button = Button6
s0_title_size = 30
s0_border_size = 7
s0_window_highlight = true
s0_highlight_color = #ffffff31

[rotate]
as_initiate_button = <Super>Button1
as_rotate_left_key = <Super>Left
as_rotate_right_key = <Super>Right
as_rotate_left_window_key = <Shift><Super>Left
as_rotate_right_window_key = <Shift><Super>Right

[wobbly]
s0_min_grid_size = 4

[move]
as_opacity = 95

[decoration]
as_command = gtk-window-decorator --replace
as_decoration_match = state=fron
as_shadow_match = !(name=gvim)

[staticswitcher]
as_next_no_popup_button = Button2

[opacify]
as_timeout = 70
s0_passive_opacity = 5

[shift]
as_initiate_key = Disabled
as_next_key = Disabled
as_prev_key = Disabled
as_next_all_key = <Alt>Tab
as_prev_all_key = <Shift><Alt>Tab
s0_mode = 1
s0_hide_all = true
s0_multioutput_mode = 2
s0_title_font_size = 30

[place]
s0_position_matches = ((name=hamster-applet) & (title=시간 추적));
s0_position_x_values = 1200;
s0_position_y_values = 1023;
s0_position_constrain_workarea = true;

[water]
as_title_wave = true

[cubeaddon]
s0_deformation = 0

[ring]
as_next_key = Disabled
as_prev_key = Disabled
as_next_all_key = <Control>Tab
as_prev_all_key = <Shift><Control>Tab
s0_title_font_size = 30

[scale]
as_initiate_key = Disabled
as_initiate_all_edge = BottomLeft|BottomRight
as_initiate_all_button = Button2
as_show_desktop = false
s0_opacity = 100

[expo]
as_expo_edge = TopLeft|TopRight
as_expo_immediate_move = true

[screenshot]
as_initiate_button = Disabled

[trailfocus]
s0_window_match = (type=toolbar | type=utility | type=dialog | type=normal) & !(state=skiptaskbar | state=skippager)  & !name=smplayer
s0_windows_count = 1
s0_windows_start = 1
s0_min_opacity = 100
s0_min_brightness = 70

[core]
as_active_plugins = core;ccp;move;resize;place;decoration;grid;workarounds;maximumize;annotate;video;crashhandler;switcher;png;titleinfo;text;dbus;glib;trailfocus;winrules;imgjpeg;wallpaper;inotify;regex;commands;wall;elements;wobbly;scale;animation;
as_audible_bell = false
as_close_window_button = Button8
as_show_desktop_key = <Super>d
s0_vsize = 2
s0_outputs = 1280x1024+0+0;1280x1024+1280+0;
s0_unredirect_fullscreen_windows = true

[winrules]
s0_skiptaskbar_match = ((name=hamster-applet) & (title=시간 추적))
s0_above_match = ((name=zim) & ((title=Calendar) | (title=TODO List - Zim))) | (name=sonata) | ((name=hamster-applet) & (title=시간 추적))
s0_sticky_match = ((name=zim) & ((title=Calendar) | (title=TODO List - Zim))) | ((name=hamster-applet) & (title=시간 추적))
s0_no_move_match = ((name=hamster-applet) & (title=시간 추적))
s0_no_minimize_match = ((name=hamster-applet) & (title=시간 추적))
s0_no_focus_match = ((name=hamster-applet) & (title=시간 추적)) | (name=sonata)

[animation]
s0_open_effects = animation:Zoom;animation:Fade;animation:None;animation:None;
s0_open_durations = 200;150;50;50;
s0_open_matches = (type=Normal | Dialog | ModalDialog | Unknown) & !(name=gnome-screensaver);(type=Notification | Utility) & !(name=compiz);(type=Tooltip) | (title=Yakuake);(type=Menu | PopupMenu | DropdownMenu);
s0_open_options = ;;;;
s0_close_effects = animation:Zoom;animation:Fade;animation:None;animation:None;
s0_close_durations = 200;150;50;50;
s0_close_matches = (type=Normal | Dialog | ModalDialog | Unknown) & !(name=gnome-screensaver);(type=Notification | Utility) & !(name=compiz);(type=Tooltip) | (title=Yakuake);(type=Menu | PopupMenu | DropdownMenu);
s0_close_options = ;;;;
s0_all_random = true

[wallpaper]
s0_bg_image = /home/beila/doc/wallpapers/Poland in Mourning.jpg;/home/beila/doc/wallpapers/Meadows Park, Scotland.jpg;/home/beila/doc/wallpapers/오래된 독일 마을 '교이굘'.jpg;/home/beila/doc/wallpapers/aft flight deck of space shuttle Discovery.jpg;
s0_bg_image_pos = 2;2;2;2;
s0_bg_fill_type = 0;0;0;0;
s0_bg_color1 = #000000ff;#000000ff;#000000ff;#000000ff;
s0_bg_color2 = #000000ff;#000000ff;#000000ff;#000000ff;

[commands]
as_command0 = /home/beila/bin/k
as_command1 = mpc disable 1
as_command2 = mpc enable 1
as_command3 = mpc next
as_command4 = mpc prev
as_run_command1_key = Scroll_Lock
as_run_command2_key = <Shift>Scroll_Lock
as_run_command3_key = <Super>x
as_run_command4_key = <Super>z
as_run_command0_button = <BottomEdge>Button2

