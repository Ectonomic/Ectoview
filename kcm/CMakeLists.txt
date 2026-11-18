# SPDX-FileCopyrightText: 2026 Ectoview contributors
# SPDX-License-Identifier: BSD-3-Clause

# One list of settings: the effect package's own (package/contents/config/main.xml) becomes this
# module's KConfigXT file, pointed at kwinrc [Effect-ectoview], so the two can't drift apart.
set(_package_xml ${CMAKE_SOURCE_DIR}/package/contents/config/main.xml)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${_package_xml})
file(READ ${_package_xml} _kcfg)
string(REPLACE "<kcfgfile name=\"\"/>" "<kcfgfile arg=\"true\"/>" _kcfg "${_kcfg}")
string(REPLACE "<group name=\"\">" "<group name=\"Effect-ectoview\">" _kcfg "${_kcfg}")
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/ectoviewconfig.kcfg "${_kcfg}")
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/ectoviewconfig.kcfgc
"File=ectoviewconfig.kcfg
ClassName=EctoviewConfig
NameSpace=Ectoview
Singleton=true
Mutators=true
")

set(kwin_ectoview_config_SOURCES ectoviewkcm.cpp ectoviewkcm.h)
kconfig_add_kcfg_files(kwin_ectoview_config_SOURCES ${CMAKE_CURRENT_BINARY_DIR}/ectoviewconfig.kcfgc)

kcoreaddons_add_plugin(kwin_ectoview_config INSTALL_NAMESPACE "kwin/effects/configs" SOURCES ${kwin_ectoview_config_SOURCES})
target_compile_definitions(kwin_ectoview_config PRIVATE -DTRANSLATION_DOMAIN=\"kwin\")
target_link_libraries(kwin_ectoview_config
    Qt6::Widgets
    Qt6::DBus
    KF6::ConfigCore
    KF6::ConfigGui
    KF6::ConfigWidgets
    KF6::CoreAddons
    KF6::GlobalAccel
    KF6::I18n
    KF6::KCMUtils
    KF6::WidgetsAddons
    KF6::XmlGui
)

# the settings window's icon and name in Plasma's taskbar (kcmshell6 names the window after the module)
install(FILES kwin_ectoview_config.desktop DESTINATION ${KDE_INSTALL_APPDIR})
