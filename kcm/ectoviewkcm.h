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

#include <QHash>
#include <QWidget>

class KShortcutsEditor;
class QCheckBox;
class QComboBox;
class QLabel;
class QListWidget;
class QListWidgetItem;
class QPushButton;
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

    // a desktop group (design proposal 4): kwinrc [Effect-ectoview] Groups holds "id:name" each
    struct Group {
        QString id;
        QString name;
    };

private:
    void updateUnmanagedState();
    QString primaryScreenText() const;

    // ---- desktop groups: the same groups Ectoview's pill lists, and each desktop's group
    void showGroups();
    void addGroup();
    void removeGroup();
    void moveGroup(int by);
    void groupRenamed(QListWidgetItem *item);
    void updateGroupButtons();
    QString groupOf(const QString &desktopId) const;
    QString nextGroupName() const;
    // what Ectoview reads: Groups and DesktopGroups, written the way Ectoview writes them
    QStringList groupsEntry() const;
    QStringList membershipEntry() const;

    ScreenChoice *m_screens = nullptr;
    KShortcutsEditor *m_shortcuts = nullptr;
    QCheckBox *m_perScreenDesktops = nullptr;
    QLabel *m_screenHint = nullptr;
    bool m_loadedPerScreenDesktops = false;
    QListWidget *m_groupList = nullptr;
    QPushButton *m_renameGroup = nullptr;
    QPushButton *m_removeGroup = nullptr;
    QPushButton *m_groupUp = nullptr;
    QPushButton *m_groupDown = nullptr;
    // one group picker per desktop KWin has, by its id
    QList<QComboBox *> m_desktopPickers;
    QList<Group> m_groups;
    QHash<QString, QString> m_membership;
    QStringList m_loadedGroups;
    QStringList m_loadedMembership;
    bool m_showing = false;
};

} // namespace Ectoview
