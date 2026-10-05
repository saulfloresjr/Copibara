# dmgbuild settings for Copibara's installer window.
#
# Mirrors Yapivo's installer (the "dmg" block in yapivo-mac-app/package.json, which
# electron-builder feeds to the same dmgbuild tool): warm off-white background,
# 660x420 window, 128 px icons, the app on the left and Applications on the right,
# so every Split Mask installer looks the same.
#
# Used by build.sh:  dmgbuild -s dmg-settings.py -D app=/path/Copibara.app NAME out.dmg
import os.path

app = defines["app"]            # noqa: F821  (dmgbuild injects `defines`)
app_name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}

background = "#F4EFEA"
window_rect = ((200, 120), (660, 420))
icon_size = 128
text_size = 13
icon_locations = {
    app_name: (198, 200),
    "Applications": (462, 200),
}

default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
