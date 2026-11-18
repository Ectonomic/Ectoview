# Ectoview for Fedora, built in COPR from the repository (.copr/Makefile makes the source
# archive). It installs beside KDE's Overview and replaces none of KWin's files: the effect in
# KWin's effects folder, its settings page, its icon. After installing, each person turns it on
# with `ectoview-setup on` (and `ectoview-setup off` before removing the package).
%{!?snapinfo: %global snapinfo 0}

Name:           ectoview
Version:        1.0.0
Release:        0.%{snapinfo}%{?dist}
Summary:        KDE Plasma's Overview, with desktop groups and notification beacons
License:        GPL-2.0-or-later AND (LGPL-2.1-only OR LGPL-3.0-only) AND OFL-1.1
URL:            https://github.com/Ectonomic/Ectoview
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cmake make gcc-c++ extra-cmake-modules
BuildRequires:  cmake(Qt6Core) cmake(Qt6Gui) cmake(Qt6Widgets) cmake(Qt6DBus)
BuildRequires:  cmake(KF6Config) cmake(KF6ConfigWidgets) cmake(KF6CoreAddons) cmake(KF6GlobalAccel)
BuildRequires:  cmake(KF6I18n) cmake(KF6KCMUtils) cmake(KF6WidgetsAddons) cmake(KF6XmlGui)

# the effect is QML that KWin runs: KWin 6.7 or newer, and the QML modules it imports
Requires:       kwin >= 6.7
Requires:       plasma-milou libplasma kf6-kirigami kf6-ksvg kf6-kcmutils qt6-qt5compat qt6-qtdeclarative
# ectoview-setup: KDE's settings tools and GLib's gdbus
Requires:       kf6-kconfig glib2

%description
Ectoview is KDE Plasma's Overview, evolved: desktop groups you step through, a dot
on each desktop that has a window asking for you, desktops you drag into order, and
a look of its own or your KDE colors. It installs beside Overview; run
`ectoview-setup on` to use it in Overview's place.

%prep
%autosetup -p1

%build
export CFLAGS="%{optflags}" CXXFLAGS="%{optflags}" LDFLAGS="%{?build_ldflags}"
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX=%{_prefix}
cmake --build build %{?_smp_mflags}

%install
DESTDIR=%{buildroot} cmake --install build
# the effect, where KWin 6.7 and 6.8 both look (its views in contents/ui/impl, main.qml's default)
mkdir -p %{buildroot}%{_datadir}/kwin/effects/ectoview
cp -r package/. %{buildroot}%{_datadir}/kwin/effects/ectoview/
if [ -e %{buildroot}%{_datadir}/icons/hicolor/icon-theme.cache ]; then rm -- %{buildroot}%{_datadir}/icons/hicolor/icon-theme.cache; fi
# the switch, the same code install.sh uses
install -Dm755 tools/install/ectoview-setup %{buildroot}%{_bindir}/ectoview-setup
install -Dm644 -t %{buildroot}%{_datadir}/%{name}/install tools/install/common.sh

%files
%license LICENSES/* package/contents/fonts/OFL.txt
%doc README.md
%{_bindir}/ectoview-setup
%{_datadir}/%{name}/
%{_datadir}/kwin/effects/ectoview/
%{_qt6_plugindir}/kwin/effects/configs/kwin_ectoview_config.so
%{_datadir}/applications/kwin_ectoview_config.desktop
%{_datadir}/icons/hicolor/*/apps/ectoview.svg

%changelog
* Tue Nov 17 2026 Ectoview contributors - 1.0.0-0
- First package: Ectoview 1.0.0, built in COPR
