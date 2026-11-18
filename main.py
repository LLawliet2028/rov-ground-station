import os
import sys
from pathlib import Path

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

from backend import Backend


def main():
    # Single-threaded scene-graph rendering: fewer native threads, avoids driver/threading crashes.
    os.environ.setdefault("QSG_RENDER_LOOP", "basic")
    QQuickStyle.setStyle("Basic")          # unstyled base so the QML can fully theme controls
    app = QGuiApplication(sys.argv)
    app.setApplicationName("ROV Ground Station")

    backend = Backend()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).with_name("Main.qml"))))
    if not engine.rootObjects():
        backend.shutdown()
        return 1

    code = app.exec()

    # Tear down in a deliberate order: QML engine first (its bindings read `backend`),
    # then the backend + sim thread, and the QGuiApplication last.
    # Letting Python free these in arbitrary order crashes on some Qt/PySide builds.
    del engine
    backend.shutdown()
    del backend
    return code


if __name__ == "__main__":
    sys.exit(main())
