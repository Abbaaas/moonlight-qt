#pragma once

#include <QObject>
#include <QHash>
#include <QByteArray>
#include <QElapsedTimer>
#include <QPoint>
#include <QQmlAbstractUrlInterceptor>

#include "SDL_compat.h"

class QQmlEngine;

// Shared state for Big Picture mode, exposed to QML as the "BigPicture"
// singleton. One instance exists for the life of the app.
//
// Input tracking: Big Picture prompts follow the device in use. Controller
// input is reported by SdlGamepadKeyNavigation *before* it is turned into
// Qt key events, so a controller press can never look like keyboard input.
// Real keyboard, mouse-button, wheel and mouse-move events are seen by an
// application event filter (spontaneous events only, so synthetic keys and
// hover updates are ignored). While Big Picture is active, controller input
// hides the mouse cursor and keyboard/mouse input shows it again.
class BigPicture : public QObject
{
    Q_OBJECT

    // "gamepad" or "keyboard"
    Q_PROPERTY(QString inputMode READ inputMode NOTIFY inputChanged)
    // "xbox", "playstation", "generic" (unrecognized controller) or "keyboard"
    Q_PROPERTY(QString glyphs READ glyphs NOTIFY inputChanged)
    // Set by the Big Picture screens while one of them is showing
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    // True when started as Moonlight.BigPicture.exe
    Q_PROPERTY(bool launchedDirectly READ launchedDirectly CONSTANT)

public:
    explicit BigPicture(bool launchedDirectly, QObject* parent = nullptr);
    ~BigPicture() override;

    static BigPicture* instance();

    // True if this executable's name means "open in Big Picture"
    static bool isBigPictureExecutable(const QString& exePath);

    QString inputMode() const { return m_InputMode; }
    QString glyphs() const { return m_Glyphs; }
    bool active() const { return m_Active; }
    void setActive(bool active);
    bool launchedDirectly() const { return m_LaunchedDirectly; }

    // name: "move", "select", "back", "toggle" or "error"
    Q_INVOKABLE void playSound(const QString& name);

    // Remembered selection, saved with Moonlight's settings
    Q_INVOKABLE QString lastHost() const;
    Q_INVOKABLE void setLastHost(const QString& uuid);
    Q_INVOKABLE int lastApp(const QString& hostUuid) const;
    Q_INVOKABLE void setLastApp(const QString& hostUuid, int appId);

    // Called by SdlGamepadKeyNavigation
    static void noteGamepadInput(SDL_GameController* gc);
    static void noteConnectedGamepads(const QList<SDL_GameController*>& gamepads);

signals:
    void inputChanged();
    void activeChanged();

protected:
    bool eventFilter(QObject* watched, QEvent* event) override;

private:
    static QString familyOf(SDL_GameController* gc);
    static QString guidOf(SDL_GameController* gc);

    void switchToGamepad(const QString& family);
    void switchToKeyboard();
    void applyCursor();
    const QByteArray* loadSound(const QString& name);

    bool m_LaunchedDirectly;
    bool m_Active;
    bool m_HadIntentionalInput;
    bool m_CursorHidden;
    QString m_InputMode;
    QString m_Glyphs;
    QPoint m_MouseAnchor;
    QHash<QString, QByteArray> m_Sounds;
    QElapsedTimer m_SinceLastAction;

    static BigPicture* s_Instance;
};

// Lets Big Picture screens and sounds be replaced without rebuilding:
// if Documents/MoonlightBigPicture/gui exists, any qrc:/gui/<name>.qml that
// also exists there is loaded from that folder, and sounds are read from
// Documents/MoonlightBigPicture/sounds. Restart Moonlight to pick up changes.
class BigPictureFiles
{
public:
    static QString folder();
    static void install(QQmlEngine* engine);
};

class BigPictureQmlInterceptor : public QQmlAbstractUrlInterceptor
{
public:
    explicit BigPictureQmlInterceptor(const QString& guiFolder);
    QUrl intercept(const QUrl& path, DataType type) override;

private:
    QString m_GuiFolder;
};
