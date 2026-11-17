/*
    SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "ectoviewkcm.h"

#include "ectoviewconfig.h"

#include <KActionCollection>
#include <KColorButton>
#include <KConfigGroup>
#include <KGlobalAccel>
#include <KLocalizedString>
#include <KPluginFactory>
#include <KSharedConfig>
#include <KShortcutsEditor>

#include <QAction>
#include <algorithm>
#include <QButtonGroup>
#include <QCheckBox>
#include <QComboBox>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusArgument>
#include <QDBusVariant>
#include <QFormLayout>
#include <QGridLayout>
#include <QGuiApplication>
#include <QHBoxLayout>
#include <QDateTime>
#include <QLabel>
#include <QListWidget>
#include <QProcess>
#include <QPushButton>
#include <QRadioButton>
#include <QScreen>
#include <QSlider>
#include <QHeaderView>
#include <QTabWidget>
#include <QTreeWidget>
#include <QVBoxLayout>

K_PLUGIN_CLASS(Ectoview::EctoviewEffectConfig)

namespace Ectoview
{

// KWin's own switch for desktops per screen (System Settings > Virtual Desktops)
static const QString s_kwinrc = QStringLiteral("kwinrc");
static const QString s_windowsGroup = QStringLiteral("Windows");
static const QString s_perOutputKey = QStringLiteral("PerOutputVirtualDesktops");
static constexpr bool s_perOutputDefault = false; // KWin's default (src/kwin.kcfg)

static void callKWin(const QString &path, const QString &interface, const QString &method, const QVariantList &args = {})
{
    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), path, interface, method);
    message.setArguments(args);
    QDBusConnection::sessionBus().asyncCall(message);
}

// KWin's desktops in its order: (position, id, name), from org.kde.KWin.VirtualDesktopManager's
// "desktops" property (a(iss)); empty when KWin isn't there
struct KWinDesktop {
    QString id;
    QString name;
};
static QList<KWinDesktop> kwinDesktops()
{
    QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),
                                                       QStringLiteral("/VirtualDesktopManager"),
                                                       QStringLiteral("org.freedesktop.DBus.Properties"),
                                                       QStringLiteral("Get"));
    call.setArguments({QStringLiteral("org.kde.KWin.VirtualDesktopManager"), QStringLiteral("desktops")});
    const QDBusMessage reply = QDBusConnection::sessionBus().call(call, QDBus::Block, 2000);
    QList<KWinDesktop> out;
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
        return out;
    }
    const QDBusArgument arg = qvariant_cast<QDBusArgument>(qvariant_cast<QDBusVariant>(reply.arguments().constFirst()).variant());
    arg.beginArray();
    while (!arg.atEnd()) {
        int position = 0;
        KWinDesktop d;
        arg.beginStructure();
        arg >> position >> d.id >> d.name;
        arg.endStructure();
        out.append(d);
    }
    arg.endArray();
    return out;
}

// Ectoview's names for the group every desktop is in before any is made, and for Hidden
// (package/contents/ui/impl/Effect.qml: defaultGroup, hiddenGroup)
static const QString s_defaultGroup = QStringLiteral("desktops");
static const QString s_hiddenGroup = QStringLiteral("hidden");
static QString defaultGroupName()
{
    return i18nc("@item the one desktop group there is before any is made", "Desktops");
}

static QLabel *hintLabel(QWidget *parent)
{
    auto label = new QLabel(parent);
    label->setWordWrap(true);
    label->setTextFormat(Qt::RichText);
    QFont font = label->font();
    font.setPointSizeF(font.pointSizeF() * 0.9);
    label->setFont(font);
    QPalette palette = label->palette();
    palette.setColor(QPalette::WindowText, palette.color(QPalette::Disabled, QPalette::WindowText));
    label->setPalette(palette);
    label->setMaximumWidth(380);
    return label;
}

ScreenChoice::ScreenChoice(QWidget *parent)
    : QWidget(parent)
{
    auto layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    auto group = new QButtonGroup(this);
    const QString texts[] = {
        i18nc("@option:radio other screens show", "All of Ectoview, like the primary screen"),
        i18nc("@option:radio other screens show", "Only their windows, without the desktop bar and toolbar"),
        i18nc("@option:radio other screens show", "Nothing: they stay as they are"),
    };
    for (const QString &text : texts) {
        auto radio = new QRadioButton(text, this);
        layout->addWidget(radio);
        group->addButton(radio);
        m_choices.append(radio);
        connect(radio, &QRadioButton::toggled, this, [this](bool on) {
            if (on) {
                Q_EMIT otherScreensChanged();
            }
        });
    }
    m_choices.constFirst()->setChecked(true);
}

int ScreenChoice::otherScreens() const
{
    for (int i = 0; i < m_choices.size(); ++i) {
        if (m_choices[i]->isChecked()) {
            return i;
        }
    }
    return 0;
}

void ScreenChoice::setOtherScreens(int mode)
{
    m_choices[std::clamp(mode, 0, int(m_choices.size()) - 1)]->setChecked(true);
}

EctoviewEffectConfig::EctoviewEffectConfig(QObject *parent, const KPluginMetaData &data)
    : KCModule(parent, data)
{
    EctoviewConfig::instance(s_kwinrc);

    // three tabs: General, Desktop groups and Shortcuts (on one page the shortcut list got squeezed
    // into a box that scrolled inside the scrolling page, and its key editor opened out of reach)
    auto pageLayout = new QVBoxLayout(widget());
    pageLayout->setContentsMargins(0, 0, 0, 0);
    auto tabs = new QTabWidget(widget());
    tabs->setObjectName(QStringLiteral("tabs"));
    tabs->setDocumentMode(true);
    pageLayout->addWidget(tabs);
    auto generalTab = new QWidget(tabs);
    auto generalForm = new QFormLayout(generalTab);
    auto groupsTab = new QWidget(tabs);
    auto groupsForm = new QFormLayout(groupsTab);
    auto shortcutsTab = new QWidget(tabs);
    auto shortcutsLayout = new QVBoxLayout(shortcutsTab);
    tabs->addTab(generalTab, i18nc("@title:tab", "General"));
    tabs->addTab(groupsTab, i18nc("@title:tab", "Desktop groups"));
    tabs->addTab(shortcutsTab, i18nc("@title:tab", "Shortcuts"));
    QFormLayout *form = generalForm;

    // ---- Show Ectoview on
    auto screens = m_screens = new ScreenChoice(widget());
    screens->setObjectName(QStringLiteral("kcfg_OtherScreens"));
    form->addRow(i18nc("@label", "Other screens show:"), screens);
    m_screenHint = hintLabel(widget());
    m_screenHint->setText(i18nc("@info", "The primary screen always shows all of Ectoview. %1 <a href=\"kscreen\">Change in Display Configuration…</a>", primaryScreenText()));
    connect(m_screenHint, &QLabel::linkActivated, this, []() {
        QProcess::startDetached(QStringLiteral("systemsettings"), {QStringLiteral("kcm_kscreen")});
    });
    form->addRow(QString(), m_screenHint);

    // ---- KWin's per-screen desktops
    m_perScreenDesktops = new QCheckBox(i18nc("@option:check", "Switch desktops independently for each screen"), widget());
    form->addRow(i18nc("@label", "Virtual desktops:"), m_perScreenDesktops);
    auto desktopsHint = hintLabel(widget());
    desktopsHint->setText(i18nc("@info", "When off, switching desktops changes every screen at once. This is KWin's own setting, so it applies everywhere, not only in Ectoview."));
    form->addRow(QString(), desktopsHint);
    connect(m_perScreenDesktops, &QCheckBox::toggled, this, &EctoviewEffectConfig::updateUnmanagedState);

    form->addItem(new QSpacerItem(0, 12));

    // ---- Overview's three settings, in Overview's words
    auto ignoreMinimized = new QCheckBox(widget());
    ignoreMinimized->setObjectName(QStringLiteral("kcfg_IgnoreMinimized"));
    form->addRow(i18n("Ignore minimized windows:"), ignoreMinimized);
    auto organizedGrid = new QCheckBox(widget());
    organizedGrid->setObjectName(QStringLiteral("kcfg_OrganizedGrid"));
    form->addRow(i18n("Organize windows in the Grid View:"), organizedGrid);
    auto filterWindows = new QCheckBox(widget());
    filterWindows->setObjectName(QStringLiteral("kcfg_FilterWindows"));
    form->addRow(i18n("Search results include filtered windows:"), filterWindows);

    form->addItem(new QSpacerItem(0, 12));

    // ---- the layout: where the desktop bar sits, and whether the toolbar shows
    auto barPosition = new QComboBox(widget());
    barPosition->setObjectName(QStringLiteral("kcfg_BarPosition"));
    barPosition->addItem(i18nc("@item:inlistbox where the desktop bar sits", "Top"));
    barPosition->addItem(i18nc("@item:inlistbox where the desktop bar sits", "Bottom"));
    barPosition->addItem(i18nc("@item:inlistbox where the desktop bar sits", "Left"));
    barPosition->addItem(i18nc("@item:inlistbox where the desktop bar sits", "Right"));
    form->addRow(i18nc("@label:listbox", "Desktop bar:"), barPosition);
    auto showToolbar = new QCheckBox(i18nc("@option:check", "Show the toolbar: search, desktop groups and settings"), widget());
    showToolbar->setObjectName(QStringLiteral("kcfg_ShowToolbar"));
    form->addRow(i18nc("@label", "Toolbar:"), showToolbar);
    auto toolbarHint = hintLabel(widget());
    toolbarHint->setText(i18nc("@info", "Without it, typing doesn't search, and the desktop groups and settings buttons move to the end of the desktop bar."));
    form->addRow(QString(), toolbarHint);

    form->addItem(new QSpacerItem(0, 12));

    // ---- desktop groups (design proposal 4), their own tab: the groups Ectoview's pill lists, and each desktop's
    form = groupsForm;
    auto groupsBox = new QWidget(widget());
    auto groupsLayout = new QHBoxLayout(groupsBox);
    groupsLayout->setContentsMargins(0, 0, 0, 0);
    m_groupList = new QListWidget(groupsBox);
    m_groupList->setObjectName(QStringLiteral("groupList"));
    m_groupList->setMaximumWidth(220);
    m_groupList->setMaximumHeight(150);
    groupsLayout->addWidget(m_groupList);
    auto groupButtons = new QVBoxLayout;
    auto addGroupButton = new QPushButton(i18nc("@action:button add a desktop group", "Add"), groupsBox);
    m_renameGroup = new QPushButton(i18nc("@action:button", "Rename"), groupsBox);
    m_removeGroup = new QPushButton(i18nc("@action:button", "Remove"), groupsBox);
    m_groupUp = new QPushButton(i18nc("@action:button move a desktop group up the list", "Move Up"), groupsBox);
    m_groupDown = new QPushButton(i18nc("@action:button move a desktop group down the list", "Move Down"), groupsBox);
    for (QPushButton *b : {addGroupButton, m_renameGroup, m_removeGroup, m_groupUp, m_groupDown}) {
        groupButtons->addWidget(b);
    }
    groupButtons->addStretch();
    groupsLayout->addLayout(groupButtons);
    groupsLayout->addStretch();
    form->addRow(i18nc("@label", "Desktop groups:"), groupsBox);
    connect(addGroupButton, &QPushButton::clicked, this, &EctoviewEffectConfig::addGroup);
    connect(m_renameGroup, &QPushButton::clicked, this, [this]() {
        if (QListWidgetItem *item = m_groupList->currentItem(); item && (item->flags() & Qt::ItemIsEditable)) {
            m_groupList->editItem(item);
        }
    });
    connect(m_removeGroup, &QPushButton::clicked, this, &EctoviewEffectConfig::removeGroup);
    connect(m_groupUp, &QPushButton::clicked, this, [this]() {
        moveGroup(-1);
    });
    connect(m_groupDown, &QPushButton::clicked, this, [this]() {
        moveGroup(1);
    });
    connect(m_groupList, &QListWidget::currentRowChanged, this, &EctoviewEffectConfig::updateGroupButtons);
    connect(m_groupList, &QListWidget::itemChanged, this, &EctoviewEffectConfig::groupRenamed);

    auto pickersBox = new QWidget(widget());
    auto pickersGrid = new QGridLayout(pickersBox);
    pickersGrid->setContentsMargins(0, 0, 0, 0);
    pickersGrid->setHorizontalSpacing(12);
    const QList<KWinDesktop> desktops = kwinDesktops();
    for (int i = 0; i < desktops.size(); ++i) {
        auto picker = new QComboBox(pickersBox);
        picker->setObjectName(QStringLiteral("group-") + desktops[i].id);
        picker->setProperty("desktopId", desktops[i].id);
        picker->setMinimumWidth(160);
        connect(picker, &QComboBox::currentIndexChanged, this, [this, picker]() {
            if (m_showing || picker->currentIndex() < 0) {
                return;
            }
            m_membership.insert(picker->property("desktopId").toString(), picker->currentData().toString());
            updateUnmanagedState();
        });
        pickersGrid->addWidget(new QLabel(desktops[i].name, pickersBox), i, 0);
        pickersGrid->addWidget(picker, i, 1);
        m_desktopPickers.append(picker);
    }
    pickersGrid->setColumnStretch(2, 1);
    if (desktops.isEmpty()) {
        pickersGrid->addWidget(new QLabel(i18nc("@info", "KWin didn't list its desktops."), pickersBox), 0, 0);
    }
    form->addRow(i18nc("@label", "Desktops:"), pickersBox);
    auto groupsHint = hintLabel(widget());
    groupsHint->setText(i18nc("@info", "Ectoview's bar and Grid View show one desktop group at a time, and Hidden desktops stay out of both. KWin's own desktop shortcuts and Plasma's pager still show every desktop."));
    form->addRow(QString(), groupsHint);

    form->addItem(new QSpacerItem(0, 12));

    form = generalForm;
    // ---- Look, Accent, Background (Ectolens's Appearance choices)
    auto look = new QComboBox(widget());
    look->setObjectName(QStringLiteral("kcfg_Look"));
    look->addItem(i18nc("@item:inlistbox Look", "Ecto"));
    look->addItem(i18nc("@item:inlistbox Look", "KDE colors and fonts"));
    form->addRow(i18nc("@label:listbox", "Look:"), look);

    auto accentRow = new QWidget(widget());
    auto accentLayout = new QHBoxLayout(accentRow);
    accentLayout->setContentsMargins(0, 0, 0, 0);
    auto accent = new QComboBox(accentRow);
    accent->setObjectName(QStringLiteral("kcfg_Accent"));
    accent->addItem(i18nc("@item:inlistbox Accent", "Ecto green"));
    accent->addItem(i18nc("@item:inlistbox Accent", "KDE accent"));
    accent->addItem(i18nc("@item:inlistbox Accent", "Custom"));
    auto customColor = new KColorButton(accentRow);
    customColor->setObjectName(QStringLiteral("kcfg_CustomAccentColor"));
    accentLayout->addWidget(accent);
    accentLayout->addWidget(customColor);
    accentLayout->addStretch();
    connect(accent, &QComboBox::currentIndexChanged, customColor, [customColor](int index) {
        customColor->setEnabled(index == 2);
    });
    form->addRow(i18nc("@label:listbox", "Accent:"), accentRow);

    auto dimRow = new QWidget(widget());
    auto dimLayout = new QHBoxLayout(dimRow);
    dimLayout->setContentsMargins(0, 0, 0, 0);
    auto dim = new QSlider(Qt::Horizontal, dimRow);
    dim->setObjectName(QStringLiteral("kcfg_BackgroundDim"));
    dim->setRange(0, 90);
    dim->setMinimumWidth(220);
    dimLayout->addWidget(new QLabel(i18nc("@label:slider the backdrop", "Lighter"), dimRow));
    dimLayout->addWidget(dim);
    dimLayout->addWidget(new QLabel(i18nc("@label:slider the backdrop", "Darker"), dimRow));
    dimLayout->addStretch();
    form->addRow(i18nc("@label:slider", "Background:"), dimRow);

    // ---- shortcuts: Overview's four, renamed for Ectoview
    auto actionCollection = new KActionCollection(this, QStringLiteral("kwin"));
    actionCollection->setComponentDisplayName(i18n("KWin"));
    actionCollection->setConfigGroup(QStringLiteral("Ectoview"));
    actionCollection->setConfigGlobal(true);
    const struct {
        const char *name;
        QString text;
        QList<QKeySequence> keys;
    } actions[] = {
        // in the order the list shows them, like with like: opening Ectoview, then KWin's own
        // one-desktop switches (with KWin's names and defaults, the same shortcuts as System Settings >
        // Shortcuts > KWin, so desktop switching is set in one place), then within a desktop group,
        // then between groups
        {"Ectoview", i18nc("@action Ectoview is the name of a KWin effect", "Toggle Ectoview"), {QKeySequence(Qt::META | Qt::Key_W)}},
        {"Ectoview Grid View", i18nc("@action Grid View is a mode of Ectoview", "Toggle Grid View"), {QKeySequence(Qt::META | Qt::Key_G)}},
        {"Ectoview Cycle", i18nc("@action", "Cycle through Ectoview and Grid View"), {}},
        {"Ectoview Cycle Opposite", i18nc("@action", "Cycle through Grid View and Ectoview"), {}},
        {"Switch One Desktop to the Left", i18nd("kwin", "Switch One Desktop to the Left"), {QKeySequence(Qt::META | Qt::CTRL | Qt::Key_Left)}},
        {"Switch One Desktop to the Right", i18nd("kwin", "Switch One Desktop to the Right"), {QKeySequence(Qt::META | Qt::CTRL | Qt::Key_Right)}},
        {"Switch One Desktop Up", i18nd("kwin", "Switch One Desktop Up"), {QKeySequence(Qt::META | Qt::CTRL | Qt::Key_Up)}},
        {"Switch One Desktop Down", i18nd("kwin", "Switch One Desktop Down"), {QKeySequence(Qt::META | Qt::CTRL | Qt::Key_Down)}},
        {"Ectoview Previous Desktop in Desktop Group", i18nc("@action", "Switch to the previous desktop in the desktop group"), {}},
        {"Ectoview Next Desktop in Desktop Group", i18nc("@action", "Switch to the next desktop in the desktop group"), {}},
        {"Ectoview Previous Desktop Group", i18nc("@action", "Switch to the previous desktop group"), {}},
        {"Ectoview Next Desktop Group", i18nc("@action", "Switch to the next desktop group"), {}},
    };
    for (const auto &a : actions) {
        QAction *action = actionCollection->addAction(QLatin1StringView(a.name));
        action->setText(a.text);
        action->setProperty("isConfigurationAction", true);
        KGlobalAccel::self()->setGlobalShortcut(action, a.keys);
    }
    m_shortcuts = new KShortcutsEditor(widget(), KShortcutsEditor::GlobalAction);
    m_shortcuts->setObjectName(QStringLiteral("shortcuts"));
    m_shortcuts->addCollection(actionCollection);
    // the editor sorts its rows by name, which split like items apart (Toggle from Cycle, Up from
    // Down); its tree is put in the order above instead, and clicking the header doesn't re-sort it
    if (auto tree = m_shortcuts->findChild<QTreeWidget *>()) {
        tree->setSortingEnabled(false);
        tree->header()->setSortIndicatorShown(false);
        QStringList order;
        for (const auto &a : actions) {
            order.append(a.text);
        }
        for (int t = 0; t < tree->topLevelItemCount(); ++t) {
            QTreeWidgetItem *category = tree->topLevelItem(t);
            QList<QTreeWidgetItem *> rows = category->takeChildren();
            std::stable_sort(rows.begin(), rows.end(), [&order](QTreeWidgetItem *x, QTreeWidgetItem *y) {
                const auto rank = [&order](QTreeWidgetItem *item) {
                    const int at = order.indexOf(item->text(0));
                    return at < 0 ? int(order.size()) : at;
                };
                return rank(x) < rank(y);
            });
            category->addChildren(rows);
            category->setExpanded(true);
        }
    }
    // room for every row and an open key editor under one of them: the page scrolls, so a list
    // that scrolls inside it hid the key editor below its edge (you couldn't reach Custom)
    const int rowHeight = m_shortcuts->fontMetrics().height() + 14;
    m_shortcuts->setMinimumHeight((int(std::size(actions)) + 2) * rowHeight + 190);
    connect(m_shortcuts, &KShortcutsEditor::keyChange, this, &KCModule::markAsChanged);
    shortcutsLayout->addWidget(m_shortcuts);

    addConfig(EctoviewConfig::self(), widget());
}

QString EctoviewEffectConfig::primaryScreenText() const
{
    const QScreen *screen = QGuiApplication::primaryScreen();
    if (!screen) {
        return QString();
    }
    const QString model = QStringList{screen->manufacturer(), screen->model()}.join(QLatin1Char(' ')).trimmed();
    return model.isEmpty() ? i18nc("@info", "Your primary screen is %1.", screen->name())
                           : i18nc("@info %1 is a monitor's make and model, %2 its connector", "Your primary screen is %1 (%2).", model, screen->name());
}

QString EctoviewEffectConfig::groupOf(const QString &desktopId) const
{
    const QString id = m_membership.value(desktopId);
    if (id == s_hiddenGroup) {
        return id;
    }
    for (const Group &g : m_groups) {
        if (g.id == id) {
            return id;
        }
    }
    return m_groups.constFirst().id;
}

QString EctoviewEffectConfig::nextGroupName() const
{
    for (int n = m_groups.size() + 1;; ++n) {
        const QString name = i18nc("@item a new desktop group's name", "Desktop group %1", n);
        if (std::none_of(m_groups.cbegin(), m_groups.cend(), [&](const Group &g) {
                return g.name == name;
            })) {
            return name;
        }
    }
}

// as Effect.qml's writeGroups: one default group with its own name is written as no groups
QStringList EctoviewEffectConfig::groupsEntry() const
{
    if (m_groups.size() == 1 && m_groups.constFirst().id == s_defaultGroup && m_groups.constFirst().name == defaultGroupName()) {
        return {};
    }
    QStringList out;
    for (const Group &g : m_groups) {
        out.append(g.id + QLatin1Char(':') + g.name);
    }
    return out;
}

// every listed desktop with its group (with only the default group, just the hidden ones)
QStringList EctoviewEffectConfig::membershipEntry() const
{
    const bool single = groupsEntry().isEmpty();
    QStringList out;
    for (const QComboBox *picker : m_desktopPickers) {
        const QString desktop = picker->property("desktopId").toString();
        const QString group = groupOf(desktop);
        if (!(single && group == s_defaultGroup)) {
            out.append(desktop + QLatin1Char('=') + group);
        }
    }
    return out;
}

// the list of groups (Hidden last, fixed) and each desktop's picker, from m_groups and m_membership
void EctoviewEffectConfig::showGroups()
{
    m_showing = true;
    const int row = m_groupList->currentRow();
    m_groupList->clear();
    for (const Group &g : std::as_const(m_groups)) {
        auto item = new QListWidgetItem(g.name, m_groupList);
        item->setData(Qt::UserRole, g.id);
        item->setFlags(item->flags() | Qt::ItemIsEditable);
    }
    auto hidden = new QListWidgetItem(i18nc("@item the group of desktops hidden from Ectoview", "Hidden"), m_groupList);
    hidden->setData(Qt::UserRole, s_hiddenGroup);
    hidden->setFlags(Qt::ItemIsEnabled);
    hidden->setForeground(m_groupList->palette().color(QPalette::Disabled, QPalette::Text));
    m_groupList->setCurrentRow(std::clamp(row, 0, int(m_groups.size()) - 1));
    for (QComboBox *picker : std::as_const(m_desktopPickers)) {
        picker->clear();
        for (const Group &g : std::as_const(m_groups)) {
            picker->addItem(g.name, g.id);
        }
        picker->addItem(QIcon::fromTheme(QStringLiteral("view-hidden")), i18nc("@item the group of desktops hidden from Ectoview", "Hidden"), s_hiddenGroup);
        picker->setCurrentIndex(picker->findData(groupOf(picker->property("desktopId").toString())));
    }
    m_showing = false;
    updateGroupButtons();
}

void EctoviewEffectConfig::updateGroupButtons()
{
    const int row = m_groupList->currentRow();
    const bool group = row >= 0 && row < m_groups.size();
    m_renameGroup->setEnabled(group);
    m_removeGroup->setEnabled(group && m_groups.size() > 1);
    m_groupUp->setEnabled(group && row > 0);
    m_groupDown->setEnabled(group && row < m_groups.size() - 1);
}

// a new group at the end of the list, its name ready to type
void EctoviewEffectConfig::addGroup()
{
    m_groups.append({QStringLiteral("g") + QString::number(QDateTime::currentMSecsSinceEpoch(), 36), nextGroupName()});
    showGroups();
    m_groupList->setCurrentRow(m_groups.size() - 1);
    m_groupList->editItem(m_groupList->item(m_groups.size() - 1));
    updateUnmanagedState();
}

// its desktops move to the first group left; nothing is deleted
void EctoviewEffectConfig::removeGroup()
{
    const int row = m_groupList->currentRow();
    if (row < 0 || row >= m_groups.size() || m_groups.size() < 2) {
        return;
    }
    const QString gone = m_groups.takeAt(row).id;
    for (auto it = m_membership.begin(); it != m_membership.end(); ++it) {
        if (it.value() == gone) {
            it.value() = m_groups.constFirst().id;
        }
    }
    showGroups();
    updateUnmanagedState();
}

void EctoviewEffectConfig::moveGroup(int by)
{
    const int row = m_groupList->currentRow();
    const int to = row + by;
    if (row < 0 || row >= m_groups.size() || to < 0 || to >= m_groups.size()) {
        return;
    }
    // desktops not listed belong to the first group: pin them before the first group changes
    for (const QComboBox *picker : std::as_const(m_desktopPickers)) {
        const QString desktop = picker->property("desktopId").toString();
        m_membership.insert(desktop, groupOf(desktop));
    }
    m_groups.move(row, to);
    showGroups();
    m_groupList->setCurrentRow(to);
    updateUnmanagedState();
}

// an empty name keeps the old one
void EctoviewEffectConfig::groupRenamed(QListWidgetItem *item)
{
    if (m_showing) {
        return;
    }
    const QString id = item->data(Qt::UserRole).toString();
    for (Group &g : m_groups) {
        if (g.id == id) {
            if (!item->text().trimmed().isEmpty()) {
                g.name = item->text().trimmed();
            }
            break;
        }
    }
    QMetaObject::invokeMethod(this, &EctoviewEffectConfig::showGroups, Qt::QueuedConnection);
    updateUnmanagedState();
}

void EctoviewEffectConfig::load()
{
    // (from disk: Ectoview writes these settings itself while it runs)
    EctoviewConfig::self()->load();
    KCModule::load();
    m_groups.clear();
    for (const QString &entry : EctoviewConfig::self()->groups()) {
        const int at = entry.indexOf(QLatin1Char(':'));
        if (at > 0 && entry.left(at) != s_hiddenGroup) {
            m_groups.append({entry.left(at), entry.mid(at + 1)});
        }
    }
    if (m_groups.isEmpty()) {
        m_groups.append({s_defaultGroup, defaultGroupName()});
    }
    m_membership.clear();
    for (const QString &entry : EctoviewConfig::self()->desktopGroups()) {
        const int at = entry.indexOf(QLatin1Char('='));
        if (at > 0) {
            m_membership.insert(entry.left(at), entry.mid(at + 1));
        }
    }
    // hidden desktops from before groups (Ectoview carries them over too, the first time it runs)
    for (const QString &id : EctoviewConfig::self()->hiddenDesktops()) {
        if (!m_membership.contains(id)) {
            m_membership.insert(id, s_hiddenGroup);
        }
    }
    showGroups();
    m_loadedGroups = groupsEntry();
    // "only the primary screen" from before the three choices (Ectoview carries it over too)
    if (EctoviewConfig::self()->primaryScreenOnly() && EctoviewConfig::self()->otherScreens() == 0) {
        m_screens->setOtherScreens(2);
    }
    m_loadedMembership = membershipEntry();
    const KConfigGroup windows(KSharedConfig::openConfig(s_kwinrc), s_windowsGroup);
    m_loadedPerScreenDesktops = windows.readEntry(s_perOutputKey, s_perOutputDefault);
    m_perScreenDesktops->setChecked(m_loadedPerScreenDesktops);
    updateUnmanagedState();
}

void EctoviewEffectConfig::save()
{
    // the groups go in with the rest of Ectoview's settings (and the list from before groups goes)
    m_loadedGroups = groupsEntry();
    m_loadedMembership = membershipEntry();
    EctoviewConfig::self()->setGroups(m_loadedGroups);
    EctoviewConfig::self()->setDesktopGroups(m_loadedMembership);
    EctoviewConfig::self()->setHiddenDesktops({});
    EctoviewConfig::self()->setPrimaryScreenOnly(false);
    KCModule::save();
    // (KCModule writes the settings only when one of its own managed controls changed)
    EctoviewConfig::self()->save();
    m_shortcuts->save();

    const bool perScreen = m_perScreenDesktops->isChecked();
    if (perScreen != m_loadedPerScreenDesktops) {
        KConfigGroup windows(KSharedConfig::openConfig(s_kwinrc), s_windowsGroup);
        windows.writeEntry(s_perOutputKey, perScreen, KConfig::Notify);
        windows.sync();
        m_loadedPerScreenDesktops = perScreen;
        // KWin reads its options again, as System Settings > Virtual Desktops makes it do
        callKWin(QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin"), QStringLiteral("reconfigure"));
    }
    callKWin(QStringLiteral("/Effects"), QStringLiteral("org.kde.kwin.Effects"), QStringLiteral("reconfigureEffect"), {QStringLiteral("ectoview")});
    updateUnmanagedState();
}

void EctoviewEffectConfig::defaults()
{
    m_shortcuts->allDefault();
    KCModule::defaults();
    m_perScreenDesktops->setChecked(s_perOutputDefault);
    m_groups = {{s_defaultGroup, defaultGroupName()}};
    m_membership.clear();
    showGroups();
    updateUnmanagedState();
}

void EctoviewEffectConfig::updateUnmanagedState()
{
    unmanagedWidgetChangeState(m_perScreenDesktops->isChecked() != m_loadedPerScreenDesktops || groupsEntry() != m_loadedGroups
                               || membershipEntry() != m_loadedMembership);
    unmanagedWidgetDefaultState(m_perScreenDesktops->isChecked() == s_perOutputDefault && groupsEntry().isEmpty() && membershipEntry().isEmpty());
}

} // namespace Ectoview

#include "ectoviewkcm.moc"

#include "moc_ectoviewkcm.cpp"
