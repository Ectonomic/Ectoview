# SPDX-FileCopyrightText: 2026 Ectoview contributors
# SPDX-License-Identifier: BSD-3-Clause
#
# Ectoview's settings page (a KDE settings module, built against KDE Frameworks 6, not KWin).
# The effect itself is package/, QML only, installed with kpackagetool6 (install.sh).

cmake_minimum_required(VERSION 3.22)
project(ectoview VERSION 0.1.0 LANGUAGES CXX)

set(QT_MIN_VERSION 6.6.0)
set(KF_MIN_VERSION 6.0.0)

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Widgets DBus)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS Config ConfigWidgets CoreAddons GlobalAccel I18n KCMUtils WidgetsAddons XmlGui)

add_subdirectory(kcm)

feature_summary(WHAT ALL FATAL_ON_MISSING_REQUIRED_PACKAGES)

# tests/unit: the settings page against what reads its settings (run with tests/unit/run_settings_test.sh)
include(ECMAddTests)
find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Test)
ecm_add_test(tests/unit/settings_test.cpp
    TEST_NAME settings_test
    LINK_LIBRARIES Qt6::Test Qt6::Widgets Qt6::DBus KF6::KCMUtils KF6::ConfigCore KF6::CoreAddons)
target_compile_definitions(settings_test PRIVATE PLUGIN_DIR="${CMAKE_BINARY_DIR}/bin" SOURCE_DIR="${CMAKE_SOURCE_DIR}")
add_dependencies(settings_test kwin_ectoview_config)
