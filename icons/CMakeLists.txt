# SPDX-FileCopyrightText: 2026 Ectoview contributors
# SPDX-License-Identifier: BSD-3-Clause
#
# Ectoview's icon: its mark on the family's dark tile, as Ectolens's (each small size at its own
# line weight, plus the scalable master). The settings window and its taskbar entry show it.
ecm_install_icons(
    ICONS
        sc-apps-ectoview.svg
        16-apps-ectoview.svg
        22-apps-ectoview.svg
        24-apps-ectoview.svg
        32-apps-ectoview.svg
        48-apps-ectoview.svg
        64-apps-ectoview.svg
    DESTINATION ${KDE_INSTALL_ICONDIR}
    THEME hicolor
)
