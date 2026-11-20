# dmgbuild settings for the snapit DMG (dmgbuild 2.x runs this file with `defines` in scope).
#
#   dmgbuild -s packaging/dmg/settings.py -D app=PATH -D background=PATH/background.png ... snapit snapit-X.Y.Z.dmg
#
# scripts/make-dmg.sh passes every define below. The window size and the two icon centres are
# the same numbers it hands to packaging/dmg/make-background.swift, which draws the arrow
# between the icons; background@2x.png next to the background file is picked up for Retina.
import os

app = defines["app"]  # noqa: F821 (`defines` is provided by dmgbuild)
background = defines["background"]  # noqa: F821
width = int(defines["width"])  # noqa: F821
height = int(defines["height"])  # noqa: F821
app_x, app_y = int(defines["app_x"]), int(defines["app_y"])  # noqa: F821
applications_x, applications_y = int(defines["applications_x"]), int(defines["applications_y"])  # noqa: F821

app_name = os.path.basename(app)

format = "ULFO"
files = [app]
symlinks = {"Applications": "/Applications"}

window_rect = ((200, 120), (width, height))
default_view = "icon-view"
icon_size = 128
text_size = 14
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_locations = {
    app_name: (app_x, app_y),
    "Applications": (applications_x, applications_y),
}
