package app.cadenza.remote.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

enum class CadenzaIcon(
    val path: String,
) {
    PLAY("M8,5 L20,12 L8,19 Z"),
    PAUSE("M6,5 H10 V19 H6 Z M14,5 H18 V19 H14 Z"),
    NEXT("M6,5 L16,12 L6,19 Z M17,5 H20 V19 H17 Z"),
    PREVIOUS("M18,5 V19 L8,12 Z M4,5 H7 V19 H4 Z"),
    MUSIC("M10,4 H20 V8 H14 V17 C14,21 6,22 6,18 C6,15 10,14 10,15 Z"),
    QR(
        "M3,3 H9 V9 H3 Z M15,3 H21 V9 H15 Z M3,15 H9 V21 H3 Z M13,13 H16 V16 H13 Z M18,13 H21 V16 H18 Z M13,18 H16 V21 H13 Z M18,18 H21 V21 H18 Z",
    ),
    SEARCH("M10,3 C1,3 1,17 10,17 C19,17 19,3 10,3 Z M10,6 C15,6 15,14 10,14 C5,14 5,6 10,6 Z M15,15 L22,21 L20,23 L14,17 Z"),
    QUEUE("M3,4 H21 V7 H3 Z M3,10 H21 V13 H3 Z M3,16 H16 V19 H3 Z"),
    LYRICS("M3,3 H21 V6 H3 Z M3,9 H16 V12 H3 Z M3,15 H21 V18 H3 Z M3,21 H12 V23 H3 Z"),
    ANALYTICS("M3,15 H7 V22 H3 Z M10,9 H14 V22 H10 Z M17,3 H21 V22 H17 Z"),
    SETTINGS("M3,5 H21 V8 H3 Z M3,16 H21 V19 H3 Z M7,2 H11 V11 H7 Z M14,13 H18 V22 H14 Z"),
    WIFI("M2,8 C7,3 17,3 22,8 L20,10 C16,6 8,6 4,10 Z M5,12 C8,9 16,9 19,12 L17,14 C14,12 10,12 7,14 Z M8,16 C10,14 14,14 16,16 L12,20 Z"),
    BLUETOOTH("M12,2 V22 L20,14 L14,9 L20,4 L12,2 M12,2 L12,22 L4,14 L10,9 L4,4 L12,2"),
    BIDIRECTIONAL("M7,3 L3,7 L7,11 M3,7 H20 M17,13 L21,17 L17,21 M21,17 H4"),
    WIFI_OFF(
        "M2,8 C7,3 17,3 22,8 L20,10 C16,6 8,6 4,10 Z M5,12 C8,9 16,9 19,12 L17,14 C14,12 10,12 7,14 Z M8,16 C10,14 14,14 16,16 L12,20 Z M3,3 L21,21 L19,23 L1,5 Z",
    ),
    BACK("M14,4 L6,12 L14,20 L16,18 L10,12 L16,6 Z M8,11 H22 V13 H8 Z"),
    UP("M4,15 L12,7 L20,15 L18,17 L12,11 L6,17 Z"),
    DOWN("M4,9 L6,7 L12,13 L18,7 L20,9 L12,17 Z"),
    CLOSE("M5,3 L12,10 L19,3 L21,5 L14,12 L21,19 L19,21 L12,14 L5,21 L3,19 L10,12 L3,5 Z"),
    LOCK("M6,10 V7 C6,0 18,0 18,7 V10 H20 V22 H4 V10 Z M9,10 H15 V7 C15,3 9,3 9,7 Z"),
    STAR("M12,2 L15,9 L22,9 L16.5,13.5 L18.5,21 L12,17 L5.5,21 L7.5,13.5 L2,9 L9,9 Z"),
}

@Composable
fun cadenzaVector(icon: CadenzaIcon): ImageVector =
    remember(icon) {
        ImageVector
            .Builder(icon.name, 24.dp, 24.dp, 24f, 24f)
            .addPath(PathParser().parsePathString(icon.path).toNodes(), fill = SolidColor(Color.Black))
            .build()
    }
