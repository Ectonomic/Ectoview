/*
    SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Ectoview's settings page, opened from System Settings > Window Management > Desktop Effects.
    Overview's page (upstream/kwin-6.7.5-overview/kcm) plus Ectoview's own settings and KWin's
    per-screen desktops switch.
*/
#pragma once

#include <KCModule>

#include <QWidget>

class KShortcutsEditor;
class QCheckBox;
class QLabel;
class QRadioButton;

namespace Ectoview
{

// "Other screens": three radio buttons that read and write one setting (OtherScreens: 0 all of
// Ectoview, 1 only their windows, 2 left as they are), so KConfig's widget manager can handle them
// as one widget
class ScreenChoice : public QWidget
{
    Q_OBJECT
    Q_PROPERTY(int otherScreens READ otherScreens WRITE setOtherScreens NOTIFY otherScreensChanged USER true)

public:
    explicit ScreenChoice(QWidget *parent = nullptr);
    int otherScreens() const;
    void setOtherScreens(int mode);

Q_SIGNALS:
    void otherScreensChanged();

private:
    QList<QRadioButton *> m_choices;
};

class EctoviewEffectConfig : public KCModule
{
    Q_OBJECT

public:
    EctoviewEffectConfig(QObject *parent, const KPluginMetaData &data);

    void load() override;
    void save() override;
    void defaults() override;

private:
    void updateUnmanagedState();
    QString primaryScreenText() const;

    ScreenChoice *m_screens = nullptr;
    KShortcutsEditor *m_shortcuts = nullptr;
    QCheckBox *m_perScreenDesktops = nullptr;
    QLabel *m_screenHint = nullptr;
    bool m_loadedPerScreenDesktops = false;
};

} // namespace Ectoview
