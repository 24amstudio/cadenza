# Wire models use explicit org.json parsing; no reflective model keep rules are needed.

# AndroidViewModelFactory resolves this constructor reflectively in the installed app.
-keepclassmembers class app.cadenza.remote.RemoteModel {
    public <init>(android.app.Application);
}
