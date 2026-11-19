/*
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The settings page against what reads it: loads the built module the way System Settings does
    (by its plugin), changes its controls, saves, and reads kwinrc back. Ectoview reads
    [Effect-ectoview] (package/contents/config/main.xml); KWin reads [Windows] PerOutputVirtualDesktops.
    Runs in Qt's test mode (its own config folder) on a private D-Bus (see run_settings_test.sh).
*/

#include <KCModule>
#include <KConfigGroup>
#include <KPluginFactory>
#include <KPluginMetaData>
#include <KSharedConfig>

#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QCoreApplication>
#include <QAction>
#include <QFile>
#include <QRegularExpression>
#include <QScrollBar>
#include <QTabWidget>
#include <QTreeView>
#include <QTreeWidget>
#include <QLabel>
#include <QPushButton>
#include <QRadioButton>
#include <QSlider>
#include <QStandardPaths>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusVariant>
#include <QDBusVirtualObject>
#include <QTest>
#include <QThread>

// A stand-in KWin on the test's own D-Bus: org.kde.KWin /VirtualDesktopManager answers "desktops"
// (a(iss): position, id, name) as KWin does, from its own thread so the page's blocking call can wait.
struct FakeDesktop {
    int position;
    QString id;
    QString name;
};
Q_DECLARE_METATYPE(FakeDesktop)
QDBusArgument &operator<<(QDBusArgument &a, const FakeDesktop &d)
{
    a.beginStructure();
    a << d.position << d.id << d.name;
    a.endStructure();
    return a;
}
const QDBusArgument &operator>>(const QDBusArgument &a, FakeDesktop &d)
{
    a.beginStructure();
    a >> d.position >> d.id >> d.name;
    a.endStructure();
    return a;
}
class FakeDesktopManager : public QDBusVirtualObject
{
public:
    QString introspect(const QString &) const override
    {
        return QString();
    }
    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        if (message.member() != QLatin1StringView("Get")) {
            return false;
        }
        const QList<FakeDesktop> desktops = {{0, QStringLiteral("w1"), QStringLiteral("Work")},
                                             {1, QStringLiteral("c0"), QStringLiteral("Code")},
                                             {2, QStringLiteral("c1"), QStringLiteral("Chat 1")}};
        connection.send(message.createReply(QVariant::fromValue(QDBusVariant(QVariant::fromValue(desktops)))));
        return true;
    }
};
class FakeKWin : public QThread
{
public:
    void run() override
    {
        qDBusRegisterMetaType<FakeDesktop>();
        qDBusRegisterMetaType<QList<FakeDesktop>>();
        QDBusConnection bus = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-kwin"));
        FakeDesktopManager manager;
        bus.registerVirtualObject(QStringLiteral("/VirtualDesktopManager"), &manager);
        bus.registerService(QStringLiteral("org.kde.KWin"));
        exec();
    }
};

class SettingsTest : public QObject
{
    Q_OBJECT

private:
    KCModule *m_module = nullptr;

    template<typename T>
    T *find(const QString &name)
    {
        T *w = m_module->widget()->findChild<T *>(name);
        if (!w) {
            qFatal("no %s on the settings page", qPrintable(name));
        }
        return w;
    }
    QRadioButton *radio(const QString &text)
    {
        const auto all = m_module->widget()->findChildren<QRadioButton *>();
        for (QRadioButton *r : all) {
            if (r->text() == text) {
                return r;
            }
        }
        qFatal("no radio button '%s'", qPrintable(text));
        return nullptr;
    }
    QCheckBox *checkBox(const QString &text)
    {
        const auto all = m_module->widget()->findChildren<QCheckBox *>();
        for (QCheckBox *c : all) {
            if (c->text() == text) {
                return c;
            }
        }
        qFatal("no check box '%s'", qPrintable(text));
        return nullptr;
    }
    KConfigGroup group(const QString &name)
    {
        auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
        config->reparseConfiguration();
        return config->group(name);
    }

private Q_SLOTS:
    void initTestCase()
    {
        static FakeKWin kwin;
        kwin.start();
        QTest::qWait(300);
        QStandardPaths::setTestModeEnabled(true);
        QFile::remove(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/kwinrc"));
        // found by name, the way System Settings finds it (EffectsModel::requestConfigure)
        QCoreApplication::addLibraryPath(QStringLiteral(PLUGIN_DIR));
        // (like Overview's, the module carries no JSON metadata; KCMultiDialog loads it all the same)
        const KPluginMetaData data(QStringLiteral("kwin/effects/configs/kwin_ectoview_config"), KPluginMetaData::AllowEmptyMetaData);
        QVERIFY2(data.isValid(), "the built settings module isn't a valid plugin");
        auto result = KPluginFactory::instantiatePlugin<KCModule>(data, this);
        QVERIFY2(result, qPrintable(result.errorText));
        m_module = result.plugin;
        m_module->load();
    }

    // ECTOVIEW_SHOT=file.png: a picture of the whole page, for looking at it (not a check)
    void picture()
    {
        const QString path = qEnvironmentVariable("ECTOVIEW_SHOT");
        if (path.isEmpty()) {
            QSKIP("ECTOVIEW_SHOT not set");
        }
        QWidget *page = m_module->widget();
        page->resize(900, page->sizeHint().height());
        page->show();
        QTest::qWait(300);
        QVERIFY(page->grab().save(path));
    }

    // every shortcut the effect declares (its ShortcutHandlers in Effect.qml) is on the page, with
    // KWin's own desktop left, right, up and down, and the list shows them all without a scrollbar of its own
    void shortcutsAreAllThereAndReachable()
    {
        QFile effect(QStringLiteral(SOURCE_DIR "/package/contents/ui/impl/Effect.qml"));
        QVERIFY(effect.open(QIODevice::ReadOnly));
        const QString qml = QString::fromUtf8(effect.readAll());
        QStringList names;
        static const QRegularExpression handler(QStringLiteral("ShortcutHandler \\{\\s*name: \"([^\"]+)\""));
        for (auto it = handler.globalMatch(qml); it.hasNext();) {
            names.append(it.next().captured(1));
        }
        QVERIFY2(names.size() >= 8, qPrintable(names.join(QLatin1Char(','))));
        names << QStringLiteral("Switch One Desktop to the Left") << QStringLiteral("Switch One Desktop to the Right")
              << QStringLiteral("Switch One Desktop Up") << QStringLiteral("Switch One Desktop Down");
        auto editor = find<QWidget>(QStringLiteral("shortcuts"));
        // (the page's actions, in its action collection)
        QStringList listed;
        const auto actions = m_module->findChildren<QAction *>();
        for (const QAction *a : actions) {
            listed.append(a->objectName());
        }
        for (const QString &n : std::as_const(names)) {
            QVERIFY2(listed.contains(n), qPrintable(QStringLiteral("not on the settings page: ") + n));
        }
        // laid out as the page lays it out, on its tab, with every row open, the list doesn't scroll
        auto tabs = find<QTabWidget>(QStringLiteral("tabs"));
        for (int i = 0; i < tabs->count(); ++i) {
            if (tabs->tabText(i).remove(QLatin1Char('&')) == QStringLiteral("Shortcuts")) {
                tabs->setCurrentIndex(i);
            }
        }
        QCOMPARE(tabs->currentWidget()->findChild<QWidget *>(QStringLiteral("shortcuts")), editor);
        QWidget *page = m_module->widget();
        page->resize(700, page->sizeHint().height());
        page->show();
        QTest::qWait(200);
        auto tree = editor->findChild<QTreeView *>();
        QVERIFY(tree);
        tree->expandAll();
        QTest::qWait(200);
        // every row (the actions and KWin's heading) and an open key editor under one of them, about
        // three rows tall, fit without the list scrolling
        const int rowHeight = tree->sizeHintForRow(0);
        const int rows = int(names.size()) + 1;
        QVERIFY2(tree->viewport()->height() >= (rows + 3) * rowHeight,
                 qPrintable(QStringLiteral("the shortcut list has %1 px for %2 px of rows and an open key editor").arg(tree->viewport()->height()).arg((rows + 3) * rowHeight)));
        page->hide();
    }

    // like items sit together in the list, never split between others, whatever their names sort to: opening Ectoview, KWin's
    // one-desktop switches, within a desktop group, between groups; read off the action names
    void shortcutsKeepLikeItemsTogether()
    {
        auto editor = find<QWidget>(QStringLiteral("shortcuts"));
        auto tree = editor->findChild<QTreeWidget *>();
        QVERIFY(tree);
        QHash<QString, QString> nameOf;  // shown text -> action name
        const auto actions = m_module->findChildren<QAction *>();
        for (const QAction *a : actions) {
            nameOf.insert(a->text().remove(QLatin1Char('&')), a->objectName());
        }
        const auto kind = [](const QString &name) {
            if (!name.startsWith(QStringLiteral("Ectoview"))) {
                return QStringLiteral("KWin's one-desktop switches");
            }
            if (name.endsWith(QStringLiteral("in Desktop Group"))) {
                return QStringLiteral("within a desktop group");
            }
            if (name.endsWith(QStringLiteral("Desktop Group"))) {
                return QStringLiteral("between desktop groups");
            }
            return QStringLiteral("opening Ectoview");
        };
        QStringList seen, shown;
        QString last;
        for (int t = 0; t < tree->topLevelItemCount(); ++t) {
            for (int i = 0; i < tree->topLevelItem(t)->childCount(); ++i) {
                const QString text = tree->topLevelItem(t)->child(i)->text(0);
                const QString k = kind(nameOf.value(text, text));
                shown.append(text);
                if (k != last) {
                    QVERIFY2(!seen.contains(k), qPrintable(QStringLiteral("%1 split apart: %2").arg(k, shown.join(QStringLiteral(" | ")))));
                    seen.append(k);
                    last = k;
                }
            }
        }
        QCOMPARE(seen.size(), 4);
        // and the pairs read in order: left before right, up before down, previous before next
        const auto before = [&shown](const char *a, const char *b) {
            return shown.indexOf(QString::fromLatin1(a)) < shown.indexOf(QString::fromLatin1(b));
        };
        QVERIFY2(before("Switch One Desktop to the Left", "Switch One Desktop to the Right") && before("Switch One Desktop Up", "Switch One Desktop Down")
                     && before("Switch to the previous desktop in the desktop group", "Switch to the next desktop in the desktop group")
                     && before("Switch to the previous desktop group", "Switch to the next desktop group"),
                 qPrintable(shown.join(QStringLiteral(" | "))));
    }

    // the settings window's name and icon come from the module's own description, read as kcmshell6
    // reads it (no allowance for an empty one), and its icon and desktop entry are in the source
    void windowGetsEctoviewsNameAndIcon()
    {
        const KPluginMetaData data(QStringLiteral("kwin/effects/configs/kwin_ectoview_config"));
        QVERIFY2(data.isValid(), "the settings module carries no description: kcmshell6 names its window \"kcmshell6\" with no icon");
        QCOMPARE(data.name(), QStringLiteral("Ectoview"));
        QCOMPARE(data.iconName(), QStringLiteral("ectoview"));
        for (const char *size : {"sc", "16", "22", "24", "32", "48", "64"}) {
            QVERIFY2(QFile::exists(QStringLiteral(SOURCE_DIR "/icons/%1-apps-%2.svg").arg(QLatin1String(size), data.iconName())), size);
        }
        QFile entry(QStringLiteral(SOURCE_DIR "/kcm/%1.desktop").arg(data.pluginId()));
        QVERIFY2(entry.open(QIODevice::ReadOnly), "no desktop entry under the name kcmshell6 gives the window");
        QVERIFY(QString::fromUtf8(entry.readAll()).contains(QStringLiteral("\nIcon=") + data.iconName() + QLatin1Char('\n')));
    }

    void startsAtTheDefaults()
    {
        QVERIFY(radio(QStringLiteral("All of Ectoview, like the primary screen"))->isChecked());
        QVERIFY(!radio(QStringLiteral("Only their windows, without the desktop bar and toolbar"))->isChecked());
        QCOMPARE(find<QComboBox>(QStringLiteral("kcfg_Look"))->currentIndex(), 0);
        QCOMPARE(find<QComboBox>(QStringLiteral("kcfg_Accent"))->currentIndex(), 0);
        QCOMPARE(find<QSlider>(QStringLiteral("kcfg_BackgroundDim"))->value(), 62);
        QVERIFY(!checkBox(QStringLiteral("Switch desktops independently for each screen"))->isChecked());
        QCOMPARE(find<QComboBox>(QStringLiteral("kcfg_BarPosition"))->currentIndex(), 0);
        QVERIFY(find<QCheckBox>(QStringLiteral("kcfg_ShowToolbar"))->isChecked());
        QVERIFY(find<QCheckBox>(QStringLiteral("kcfg_ShowSideArrows"))->isChecked());
    }

    void savesWhatEctoviewAndKWinRead()
    {
        radio(QStringLiteral("Only their windows, without the desktop bar and toolbar"))->click();
        find<QComboBox>(QStringLiteral("kcfg_Look"))->setCurrentIndex(1);
        find<QComboBox>(QStringLiteral("kcfg_Accent"))->setCurrentIndex(1);
        find<QSlider>(QStringLiteral("kcfg_BackgroundDim"))->setValue(40);
        find<QCheckBox>(QStringLiteral("kcfg_IgnoreMinimized"))->setChecked(true);
        find<QComboBox>(QStringLiteral("kcfg_BarPosition"))->setCurrentIndex(3);
        find<QCheckBox>(QStringLiteral("kcfg_ShowToolbar"))->setChecked(false);
        find<QCheckBox>(QStringLiteral("kcfg_ShowSideArrows"))->setChecked(false);
        checkBox(QStringLiteral("Switch desktops independently for each screen"))->click();
        QVERIFY2(m_module->needsSave(), "changing the controls didn't mark the page as changed");
        m_module->save();

        const KConfigGroup ectoview = group(QStringLiteral("Effect-ectoview"));
        QCOMPARE(ectoview.readEntry("OtherScreens", 0), 1);
        QCOMPARE(ectoview.readEntry("Look", 0), 1);
        QCOMPARE(ectoview.readEntry("Accent", 0), 1);
        QCOMPARE(ectoview.readEntry("BackgroundDim", 0), 40);
        QCOMPARE(ectoview.readEntry("IgnoreMinimized", false), true);
        QCOMPARE(ectoview.readEntry("BarPosition", 0), 3);
        QCOMPARE(ectoview.readEntry("ShowToolbar", true), false);
        QCOMPARE(ectoview.readEntry("ShowSideArrows", true), false);
        QCOMPARE(group(QStringLiteral("Windows")).readEntry("PerOutputVirtualDesktops", false), true);
    }

    void readsBackWhatIsSaved()
    {
        m_module->load();
        QVERIFY(radio(QStringLiteral("Only their windows, without the desktop bar and toolbar"))->isChecked());
        QVERIFY(!radio(QStringLiteral("All of Ectoview, like the primary screen"))->isChecked());
        QVERIFY(checkBox(QStringLiteral("Switch desktops independently for each screen"))->isChecked());
        QVERIFY(!m_module->needsSave());
    }

    QStringList entry(const QString &key)
    {
        return group(QStringLiteral("Effect-ectoview")).readEntry(key.toUtf8().constData(), QStringList());
    }

    void primaryScreenOnlyFromBeforeIsCarriedOver()
    {
        // a kwinrc from before the three choices: "only the primary screen"
        KConfigGroup old = group(QStringLiteral("Effect-ectoview"));
        old.writeEntry("PrimaryScreenOnly", true);
        old.deleteEntry("OtherScreens");
        old.sync();
        m_module->load();
        QVERIFY2(radio(QStringLiteral("Nothing: they stay as they are"))->isChecked(), "\"only the primary screen\" from before didn't become \"they stay as they are\"");
        m_module->save();
        QCOMPARE(group(QStringLiteral("Effect-ectoview")).readEntry("OtherScreens", 0), 2);
        QVERIFY(!group(QStringLiteral("Effect-ectoview")).readEntry("PrimaryScreenOnly", false));
    }

    // desktop groups are made and changed in Ectoview only (the settings page's tab for them came
    // out November 17, 2026): the page shows no group controls, only where to find them, and never
    // writes Groups, DesktopGroups or HiddenDesktops, even after Ectoview changed them under it
    void groupsAreEctoviewsAlone()
    {
        const auto tabs = find<QTabWidget>(QStringLiteral("tabs"));
        QStringList names;
        for (int i = 0; i < tabs->count(); ++i) {
            names.append(tabs->tabText(i).remove(QLatin1Char('&')));
        }
        QCOMPARE(names, (QStringList{QStringLiteral("General"), QStringLiteral("Shortcuts")}));
        QVERIFY(find<QLabel>(QStringLiteral("groupsHint"))->text().contains(QStringLiteral("in Ectoview itself")));

        const QStringList groups = {QStringLiteral("g1:Work"), QStringLiteral("g2:Games")};
        const QStringList members = {QStringLiteral("w1=g1"), QStringLiteral("c0=g2"), QStringLiteral("c1=hidden")};
        const QStringList hidden = {QStringLiteral("c9")};
        KConfigGroup ectoview = group(QStringLiteral("Effect-ectoview"));
        ectoview.writeEntry("Groups", groups);
        ectoview.writeEntry("DesktopGroups", members);
        ectoview.writeEntry("HiddenDesktops", hidden);
        ectoview.sync();
        m_module->load();
        find<QComboBox>(QStringLiteral("kcfg_Look"))->setCurrentIndex(0);
        find<QSlider>(QStringLiteral("kcfg_BackgroundDim"))->setValue(55);
        m_module->save();
        QCOMPARE(entry(QStringLiteral("Groups")), groups);
        QCOMPARE(entry(QStringLiteral("DesktopGroups")), members);
        QCOMPARE(entry(QStringLiteral("HiddenDesktops")), hidden);

        // Ectoview changes the groups while the page is open; the page's next Apply keeps Ectoview's
        const QStringList groups2 = {QStringLiteral("g2:Games"), QStringLiteral("g1:Work"), QStringLiteral("g3:Mail")};
        const QStringList members2 = {QStringLiteral("w1=g3"), QStringLiteral("c0=g2")};
        ectoview = group(QStringLiteral("Effect-ectoview"));
        ectoview.writeEntry("Groups", groups2);
        ectoview.writeEntry("DesktopGroups", members2);
        ectoview.deleteEntry("HiddenDesktops");
        ectoview.sync();
        find<QSlider>(QStringLiteral("kcfg_BackgroundDim"))->setValue(45);
        m_module->save();
        QCOMPARE(entry(QStringLiteral("Groups")), groups2);
        QCOMPARE(entry(QStringLiteral("DesktopGroups")), members2);
        QVERIFY(!group(QStringLiteral("Effect-ectoview")).hasKey("HiddenDesktops"));
    }

    void defaultsPutEverythingBack()
    {
        m_module->defaults();
        QVERIFY(radio(QStringLiteral("All of Ectoview, like the primary screen"))->isChecked());
        QVERIFY(!checkBox(QStringLiteral("Switch desktops independently for each screen"))->isChecked());
        QCOMPARE(find<QSlider>(QStringLiteral("kcfg_BackgroundDim"))->value(), 62);
        QVERIFY(find<QCheckBox>(QStringLiteral("kcfg_ShowSideArrows"))->isChecked());
        const QStringList groups = entry(QStringLiteral("Groups"));
        const QStringList members = entry(QStringLiteral("DesktopGroups"));
        m_module->save();
        // Defaults is for this page's settings: Ectoview's desktop groups stay as they are
        QVERIFY(!groups.isEmpty());
        QCOMPARE(entry(QStringLiteral("Groups")), groups);
        QCOMPARE(entry(QStringLiteral("DesktopGroups")), members);
        // KConfig stores a default by removing the key; Ectoview then reads main.xml's default (false)
        const KConfigGroup ectoview = group(QStringLiteral("Effect-ectoview"));
        QVERIFY(!ectoview.hasKey("OtherScreens") || ectoview.readEntry("OtherScreens", 0) == 0);
        QCOMPARE(group(QStringLiteral("Windows")).readEntry("PerOutputVirtualDesktops", true), false);
    }
};

QTEST_MAIN(SettingsTest)

#include "settings_test.moc"
